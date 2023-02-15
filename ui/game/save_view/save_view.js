App.SaveView = App.View.extend(Ember.ViewTargetActionSupport, {
   templateName: 'save',
   classNames: ['flex', 'fullScreen'],
   hideOnCreate: false,
   hideSaveButtons: false,
   cachedSaves: {},

   init: function() {
      var self = this;
      this._super();
      this.refreshSavesList(true);
      this._getAutoSaveSetting();

      // ACE: handle multiple auto-saves
      self._autoSaveUnique = false;

      stonehearth_ace.getModConfigSetting('stonehearth_ace', 'auto_save_unique_files', function(value) {
            self._autoSaveUnique = value;
         });
      $(top).on("auto_save_unique_files_changed", function (_, e) {
         self._autoSaveUnique = e.value;
      });
   },

   didInsertElement: function () {
      this.set('hideSave', this.hideSaveButtons);
      this.refreshSavesList(true);

      if (this.hideOnCreate) {
         this.hide();
      }
   },

   dismiss: function () {
      this.hide();
   },

   hide: function () {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }
      this._super();
   },

   show: function () {
      this._super();
      App.stonehearth.modalStack.push(this);
      this.refreshSavesList();
   },

   // grab all the saves from the server
   // ACE: handle multiple auto-saves
   refreshSavesList: function (changed) {
      var self = this;
      radiant.call("radiant:client:get_save_games")
         .done(function(json) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            
            if (!changed) {
               if (self.cachedSaves) {
                  // Check if any new saves were added
                  radiant.each(json, function(k, v) {
                     if (!self.cachedSaves[k]) {
                        changed = true;
                     }
                  });

                  // Check if any saves were deleted
                  radiant.each(self.cachedSaves, function(k, v) {
                     if (!json[k]) {
                        changed = true;
                     }
                  });
               }
            }

            // Update saves if any saves added/removed
            if (changed || !self.cachedSaves) {
               stonehearth_ace.getModConfigSetting('stonehearth_ace', 'auto_save_max_files', function(value) {
                     var maxNum = parseInt(value);
                     if (maxNum && maxNum > 0) {
                        self._deleteOldAutoSaves(json, maxNum);
                     }
                     else {
                        self._setSaves(json);
                     }
                  });
            }
         });
   },

   _setSaves: function(json) {
      var self = this;
      var formattedSaves = self._formatSaves(json);
      self.set('saves', formattedSaves);
   },

   // reformat the save map into an array sorted by time, for the view to consume
   _formatSaves: function(saves) {
      var self = this;

      var saveKey = App.stonehearthClient.gameState.saveKey;
      var vals = radiant.map_to_array(saves, function(k ,v) {
         v.key = k;
         if (k == saveKey) {
            v.current = true;
         }
         var version = v.gameinfo.save_version;
         if (!version) {
            version = 0;
         }
         if (version < App.minSupportedSaveVersion || version > App.currentSaveVersion) {
            v.differentVersions = true;
         }

         var gameDate = v.gameinfo.game_date;
         if (gameDate) {
            var dateObj = new Date(0, 0, 0, gameDate.hour, gameDate.minute);
            var localizedTime = dateObj.toLocaleTimeString(i18n.lng(), {hour: '2-digit', minute:'2-digit'});
            v.gameinfo.game_date.time = localizedTime;
         }

         if (v.gameinfo.time) {
            var savedRLDate = new Date(v.gameinfo.time);
            v.gameinfo.formatted_time = savedRLDate.toLocaleString(i18n.lng());
         }

      });

      // sort by creation time
      vals.sort(function(a, b){
         var tsA = a.gameinfo.timestamp ? a.gameinfo.timestamp : 0;
         var tsB = b.gameinfo.timestamp ? b.gameinfo.timestamp : 0;
         // sort most recent games first
         return tsB - tsA;
      });

      self.cachedSaves = saves;

      return vals;
   },

   _getAutoSaveSetting: function() {
      var self = this;

      radiant.call('radiant:get_config', 'enable_auto_save')
         .done(function(response) {
            self.set('auto_save', response.enable_auto_save == true);
         })
   },

   _toggleAutoSave: function() {
      // XXX, this pattern is a little weird, but it lets us
      // 1. use dual-binding between a checkbox and the data in the controller
      // 2. have a clean API in actions
      var enabled = this.get('auto_save');
      this.send('enableAutoSave', enabled);
   }.observes('auto_save'),

   _showSaveModal: function() {
      // show the "saving.... message"
      this.set('opInProgress', true);
      this.triggerAction({
         action:'openInOutlet',
         actionContext: {
            viewName: 'savePopup',
            outletName: 'modalmodal'
         }
      });
   },

   _hideSaveModal: function() {
      // hide the "saving.... message"
      this.set('opInProgress', false);
      this.triggerAction({
         action:'closeOutlet',
         actionContext: {
            outletName: 'modalmodal'
         }
      });
   },

   // ACE: handle multiple auto-saves and specifying save name
   _saveGame: function(saveid, saveName, onDone, onFail, onAlways) {
      var self = this;
      var d = new Date();
      var gameDate = App.gameView.getDateTime();

      if (!saveid) {
         // Generate a new saveid
         saveid = String(d.getTime());
      }

      var isAuto = false;
      var name;
      if (saveid == 'auto_save') {
         isAuto = true;
         name = i18n.t('stonehearth:ui.game.save_view.auto_save_prefix');
      } else if (saveName) {
         name = saveName;
      } else {
         name = '';
      }

      if (isAuto && self._autoSaveUnique) {
         var dateTimeStr = d.toLocaleString(window.navigator.userLanguage || window.navigator.language);
         saveid = saveid + ' ' + dateTimeStr.replace(/[/\\?%*:|"<>]/g, '-');
         name = i18n.t('stonehearth_ace:ui.game.save_view.auto_save_name',
            {i18n_data: {date_time: dateTimeStr }});
         
         // if this puts us over the gameplay setting limit of auto-saves, delete older ones until we're back to the limit
         //self._deleteOldAutoSaves();
      }

      Ember.run.scheduleOnce('afterRender', self, function() {
         var savePopup = $('#savePopup #message');
         if (savePopup) {
            savePopup.append('<br>' + (isAuto ? `<i>${saveid}</i>` : (saveName ? saveName : App.stonehearthClient.settlementName())));
            savePopup.css('text-align', 'center');
         }
      });

      return radiant.call("radiant:client:save_game", saveid, {
         name: name,
         town_name: App.stonehearthClient.settlementName(),
         game_date: gameDate,
         timestamp: d.getTime(),
         time: d.toLocaleString(),
         jobs: {
            crafters: App.jobController.getNumCrafters(),
            workers: App.jobController.getNumWorkers(),
            soldiers: App.jobController.getNumSoldiers(),
         }
      });

      // technically we don't care about this unless we're auto-saving, but it's just simpler to check every time
      // and should have virtually no performance impact
      // radiant.call('radiant:get_config', 'mods.stonehearth_ace.auto_save_unique_files')
      // .done(function(response) {
      //    var autoSaveUnique = response['mods.stonehearth_ace.auto_save_unique_files'];

      //    if (isAuto && autoSaveUnique) {
      //       var dateTimeStr = d.toLocaleString(window.navigator.userLanguage || window.navigator.language);
      //       saveid = saveid + ' ' + dateTimeStr.replace(/[/\\?%*:|"<>]/g, '-');
      //       name = i18n.t('stonehearth_ace:ui.game.save_view.auto_save_name',
      //          {i18n_data: {date_time: dateTimeStr }});
            
      //       // if this puts us over the gameplay setting limit of auto-saves, delete older ones until we're back to the limit
      //       self._deleteOldAutoSaves();
      //    }

      //    radiant.call("stonehearth_ace:save_game_command")
      //    .done(function() {
      //       radiant.call("radiant:client:save_game", saveid, {
      //          name: name,
      //          town_name: App.stonehearthClient.settlementName(),
      //          game_date: gameDate,
      //          timestamp: d.getTime(),
      //          time: d.toLocaleString(),
      //          jobs: {
      //             crafters: App.jobController.getNumCrafters(),
      //             workers: App.jobController.getNumWorkers(),
      //             soldiers: App.jobController.getNumSoldiers(),
      //          }
      //       })
      //       .done(function() { if(onDone) onDone(); })
      //       .fail(function() { if(onFail) onFail(); })
      //       .always(function() { if(onAlways) onAlways(); });
      //    })
      //    .fail(function() { if(onFail) onFail(); })
      //    .always(function() { if(onAlways) onAlways(); });
      // });
   },

   // when a controller op is in progress (saving, etc), disable the buttons
   enableButtons : function(enabled) {
      //XXX use bind-attr to do this
      var enabled = !this.get('opInProgress');

      if (this.$()) {
         if (enabled) {
            this.$('#deleteSaveButton').removeClass('disabled');
            this.$('#loadSaveButton').removeClass('disabled');
            this.$('#overwriteSaveButton').removeClass('disabled');
            this.$('#createSaveButton').removeClass('disabled');
         } else {
            this.$('#deleteSaveButton').addClass('disabled');
            this.$('#loadSaveButton').addClass('disabled');
            this.$('#overwriteSaveButton').addClass('disabled');
            this.$('#createSaveButton').addClass('disabled');
         }
      }
   }.observes('opInProgress'),

   // when the array of saves is updated, select the first save
   _selectFirstSave: function() {
      var saves = this.get('saves');
      if (saves) {
         this.set('selectedSave', saves[0]);

         var hasIncompatibleSave = false;
         for (var i=0; i<saves.length; ++i) {

            if (saves[i].differentVersions) {
               hasIncompatibleSave = true;
               break;
            }
         }
         this.set('hasIncompatibleSave', hasIncompatibleSave);
      }

   }.observes('saves'),

   // when the user selects a new save, manipulate the css classes so it highlights in the view
   _updateSelection: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function () {
         if (!this.$()) {
            return;
         }

         // Update the UI. XXX, is there a way to do this without jquery?
         var key = this.get('selectedSave.key');
         var saveSlot = this.$('.saveSlot');
         if (saveSlot) {
            saveSlot.removeClass('selected');
         }
         
         if (key) {
            this.$("[key='" + key + "']").addClass('selected');
         }

         var differentVersions = this.get('selectedSave.differentVersions');
         if (differentVersions) {
            self.$('#loadSaveButton').addClass('disabled')
                                     .tooltipster()
                                     .tooltipster('enable');
         } else {
            self.$('#loadSaveButton').removeClass('disabled')
                                     .tooltipster()
                                     .tooltipster('disable');
         }
      });

   }.observes('selectedSave'),

   _overwriteSaveGame: function(saveid, saveName) {
      var self = this;

      self._showSaveModal();
      self._saveGame(null, saveName)
            .done(function() {
               radiant.call("radiant:client:delete_save_game", saveid)
                  .always(function() {
                     self._hideSaveModal();
                     self.refreshSavesList(true);
                  })
            })
            .fail(function() {
               self._hideSaveModal();
               self.refreshSavesList();
            });
   },

   _deleteSaveGame: function(key) {
      var self = this;

      if (key) {
         self.set('opInProgress', true);
         radiant.call("radiant:client:delete_save_game", String(key))
            .always(function() {
               self.refreshSavesList(true);
               self.set('opInProgress', false);
            });
      }
   },

   // ACE: delete old auto saves when there's a cap on number of auto saves
   _deleteOldAutoSaves: function(saves_json, maxNum) {
      var self = this;
      var autoSaves = [];

      // enumerate all save files that match the auto-save name template to see if we have too many
      //var regEx = RegExp(i18n.t('stonehearth_ace:ui.game.save_view.auto_save_name',
      //                          {i18n_data: {date_time: '\(.+\)' }}));
      // we don't need to use regex, we can just check if the key starts with 'auto_save'
      // and that will then also include the non-unique auto_save file
      var keyCheck = 'auto_save';
      radiant.each(saves_json, function(k, v) {
         //var strMatch = regEx.test(v.gameinfo.name);
         var strMatch = keyCheck == k.substr(0, keyCheck.length);
         if (strMatch) {
            v.key = k;
            autoSaves.push(v);
         }
      });

      // this is post-save now, so no need to do +1
      var numToDelete = autoSaves.length - maxNum;
      if (numToDelete > 0) {
         // sort in descending order so the oldest is last, so we can just pop off the array
         autoSaves.sort(function(a, b) {
            return b.gameinfo.timestamp - a.gameinfo.timestamp;
         });
         
         // only delete a single save at a time
         //for (var i = 0; i < numToDelete; i++) {
            var save = autoSaves.pop();
            self._deleteSaveGame(save.key);
         //}
      }
      else {
         self._setSaves(saves_json);
      }
   },

   actions: {
      selectSave: function(save) {
         if (save) {
            this.set('selectedSave', save)
         }
      },

      overwriteSaveGame: function() {
         //XXX, need to handle validation in an ember-friendly way. No jquery
         if (this.$('#overwriteSaveButton').hasClass('disabled')) {
            return;
         }

         var self = this;
         var key = this.get('selectedSave.key');

         if (!key || key == '') {
            return;
         }

         // Use custom name from gameinfo if we are saving from the same town
         var name = null;
         var gameinfo = self.get('selectedSave.gameinfo');
         var customName = gameinfo.name;
         if (customName && customName != '' && gameinfo.town_name == App.stonehearthClient.settlementName()) {
            name = customName;
         }

         // open the confirmation screen
         self.triggerAction({
            action:'openInOutlet',
            actionContext: {
               viewName: 'confirm',
               outletName: 'modalmodal',
               controller: {
                  title: i18n.t('stonehearth:ui.game.save_view.confim_overwrite_title'),
                  message: i18n.t('stonehearth:ui.game.save_view.confirm_overwrite_message'),
                  buttons: [
                     {
                        label: i18n.t('stonehearth:ui.game.common.yes'),
                        click: function() {
                           radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash' });
                           self._overwriteSaveGame(key, name);
                        }
                     },
                     {
                        label: i18n.t('stonehearth:ui.game.common.no')
                     }
                  ]
               }
            }
         });
      },

      deleteSaveGame: function() {
         //XXX, need to handle validation in an ember-friendly way. No jquery
         if (this.$('#deleteSaveButton').hasClass('disabled')) {
            return;
         }

         var self = this;
         var key = this.get('selectedSave.key');

         if (!key || key == '') {
            return;
         }

         // open the confirmation screen
         self.triggerAction({
            action:'openInOutlet',
            actionContext: {
               viewName: 'confirm',
               outletName: 'modalmodal',
               controller: {
                  title: i18n.t('stonehearth:ui.game.save_view.confim_delete_title'),
                  message: i18n.t('stonehearth:ui.game.save_view.confirm_delete_message'),
                  buttons: [
                     {
                        label: i18n.t('stonehearth:ui.game.common.yes'),
                        click: function() {
                           radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash' });
                           self._deleteSaveGame(key);
                        }
                     },
                     {
                        label: i18n.t('stonehearth:ui.game.common.no')
                     }
                  ]
               }
            }
         });
      },

      deleteIncompatibleSaves: function() {
         var self = this;
         //XXX, need to handle validation in an ember-friendly way. No jquery
         if (self.$('#deleteSaveButton').hasClass('disabled')) {
            return;
         }

         var saves = this.get('saves');
         if (saves) {
            radiant.each(saves, function(i, save){
               if (save.differentVersions) {
                  self.send('deleteSaveGame', save.key);
               }
            })
         }
      },

      saveGame: function(saveid) {
         if (this.$('#deleteSaveButton').hasClass('disabled')) {
            return;
         }

         var self = this;

         self._showSaveModal();
         self._saveGame(saveid)
               .always(function() {
                  self._hideSaveModal();
                  self.refreshSavesList(true);
               });
      },

//    saveGame: function(saveid, onAlways) {
//       if (this.$('#deleteSaveButton').hasClass('disabled')) {
//          return;
//       }

//       var self = this;

//       self._showSaveModal();
//       self._saveGame(saveid, null, null, null,
//             function() {
//                self._hideSaveModal();
//                self.refreshSavesList(true);
//                if (onAlways) {
//                   onAlways();
//                }
//             });
//    }

      loadGame: function(key) {
         if (this.$('#loadSaveButton').hasClass('disabled')) {
            return;
         }
         var key = this.get('selectedSave.key');

         if (key) {
            App.stonehearthClient.showModsMatchModal(key);
            this.hide();
         }
      },

      enableAutoSave: function(enable) {
         radiant.call('radiant:set_config', 'enable_auto_save', enable);
      },

      renameSaveGame: function(saveid, newName) {
         var self = this;
         radiant.call('radiant:client:rename_save', saveid, newName)
            .always(function() {
               self.refreshSavesList();
            });
      },
   },
});

App.StonehearthSaveSlotView = App.View.extend({
   classNames: ['row'],
   templateName: '_saveSlot',
   uriProperty: 'model',

   didInsertElement: function() {
      var self = this;

      var key = self.get('save.key');
      new StonehearthInputHelper(self.$('#name'), function (value) {
         var mainView = self.get('mainView');
         mainView.send('renameSaveGame', key, value);
      });

      var description = i18n.t('stonehearth:ui.game.save_view.save_tooltip_description', {folder_name : self.get('save.key')});
      var tooltip = App.tooltipHelper.createTooltip(self.get('save.gameinfo.town_name'), description);
      self.$().tooltipster({content: $(tooltip)});
   },

   save_name: function() {
      var name = this.get('save.gameinfo.name');
      if (name) {
         return name;
      }
      return this.get('save.gameinfo.town_name');
   }.property('save.gameinfo.name', 'save.gameinfo.town_name')
});
