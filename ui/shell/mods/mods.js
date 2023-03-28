App.StonehearthModsView = App.View.extend({
   templateName: 'stonehearthMods',
   i18nNamespace: 'stonehearth',
   classNames: ['flex', 'fullScreen'],

   _installedModsList: {},
   _workshopMods: {},
   _steamUploadMods: {},
   _unmanagedMods: {},
   _workshopDownloads: {},

   init: function() {
      this._super();
      var self = this;

      radiant.call('radiant:set_workshop_polling_enabled', true);

      self._uploadView = null;
      self._createModView = null;
      self._editTemplatesView = null;
      self._confirmView = null;

      self.mod_status = App.constants.mods.mod_status;
      self.mod_type = App.constants.mods.mod_type;
      self.mod_flag = App.constants.mods.mod_flag;

      self._updateModsList();
      self.set('workshopMods', radiant.map_to_array(self._workshopMods));

      radiant.call('radiant:is_steam_present')
         .done(function(response) {
            var present = response.present;
            self.set('steamPresent', present);
            if (present) {
               self._setupSteamTraces();
            }
         });

      self._uploadView = null;
      self._createModView = null;


      self.set('unmanagedModsTitle', i18n.t('stonehearth:ui.shell.mods_menu.sections.unmanaged_mods.title'));
      self.set('workshopModsTitle', i18n.t('stonehearth:ui.shell.mods_menu.sections.workshop_mods.title'));
      self.set('steamUploadModsTitle', i18n.t('stonehearth:ui.shell.mods_menu.sections.my_items.title'));

      self._setEnabledActions();
   },

   _setupSteamTraces: function() {
      var self = this;
      radiant.call('radiant:get_steam_workshop_trace')
         .progress(function(polledItems) {
            var workshopDownloads = {};
            radiant.each(polledItems, function(key, data) {
               var entry = {};
               var typedId = data.id + App.constants.mods.mod_type.WORKSHOP_MODULE;
               var elementId = '#' + typedId;
               var existingEntry = self._workshopMods[key];
               if (existingEntry) {
                  entry = existingEntry;
                  if (data.title && existingEntry.title != data.title) {
                     // Use steam workshop title instead of manifest info.name as title
                     Ember.set(entry, 'title', data.title);
                  }
                  if ($(elementId).length) {
                     Ember.set(entry, 'isChecked', $(elementId).is(':checked'));
                  }
               } else {
                  entry = data;
                  entry.steamFileId = key;
                  entry.title = data.title || i18n.t('stonehearth:ui.shell.settings.mods_tab.loading_namespace');
                  if (data.tags) {
                     var tags = data.tags.split(',');
                     if (tags.includes('Building Templates')) {
                        entry.hasBuildingTemplates = true;
                     }
                  }
                  entry.name = data.namespace;
                  entry.modType = App.constants.mods.mod_type.WORKSHOP_MODULE;
                  entry.typedId = typedId;
                  if ($(elementId).length) {
                     Ember.set(entry, 'isChecked', $(elementId).is(':checked'));
                  } else {
                     Ember.set(entry, 'isChecked', true);
                  }
               }

               if (entry.flag != self.mod_flag.DEFAULT) {
                  switch (entry.flag) {
                     case self.mod_flag.DEBUG:
                     Ember.set(entry, 'flag_description', i18n.t('stonehearth:ui.shell.settings.mods_tab.debug'));
                     break;
                  }
               }

               Ember.set(entry, 'typedId', typedId);
               entry.state = data.state;
               entry.download_progress = data.download_progress;
               workshopDownloads[key] = entry;
            });

            // Only reconstruct the array and recreate the mod rows if
            // a workshop mod has been added or removed from the list
            if (Object.keys(self._workshopDownloads).length != Object.keys(workshopDownloads).length) {
               var workshopArray = radiant.map_to_array(workshopDownloads);
               self._sortModsByName(workshopArray);
               self.set('workshopMods', workshopArray);
            } else {
               self.set('workshopItemUpdates', workshopDownloads);
            }

            self._workshopDownloads = workshopDownloads;
         });
      

      radiant.call('radiant:get_steam_item_updates_trace')
         .progress(function(updates) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('steamUploadItemUpdates', updates);
         });
   },

   _updateModsList: function() {
      var self = this;

      self._workshopMods = {};
      self._unmanagedMods = {};
      self._steamUploadMods = {};

      radiant.call('radiant:get_all_mods')
         .done(function(mods) {
            radiant.each(mods, function(_, modData) {
                  var key = modData.name;
                  if (modData.steamFileId) {
                     modData.id = modData.steamFileId;
                  } else {
                     modData.id = "opt_mod_" + key;
                  }
                  modData.typedId = modData.id + modData.modType;

                  // override default status for RC and NA to mark them as "required"
                  if (modData.status == 0 && (key == 'rayyas_children' || key == 'northern_alliance')) {
                     modData.status = self.mod_status.REQUIRED;
                  }

                  if (modData.status != 0) {
                     modData.unavailable = true;
                     switch(modData.status) {
                        case self.mod_status.INVALID_MANIFEST:
                           modData.tooltip = i18n.t('stonehearth:ui.shell.settings.mods_tab.invalid_manifest');
                           modData.has_error = true;
                           break;
                        case self.mod_status.OUT_OF_DATE:
                           modData.tooltip = i18n.t('stonehearth:ui.shell.settings.mods_tab.out_of_date');
                           modData.has_error = true;
                           break;
                        case self.mod_status.DEFERRED_LOAD:
                           modData.tooltip = i18n.t('stonehearth:ui.shell.settings.mods_tab.deferred_load');
                           break;
                        case self.mod_status.REQUIRED:
                           modData.tooltip = i18n.t('stonehearth:ui.shell.settings.mods_tab.required');
                           break;
                     }
                  }

                  if (modData.flag != self.mod_flag.DEFAULT) {
                     switch (modData.flag) {
                        case self.mod_flag.DEBUG:
                        Ember.set(modData, 'flag_description', i18n.t('stonehearth:ui.shell.settings.mods_tab.debug'));
                        break;
                     }
                  }

                  if ($(modData.id).length) {
                     modData.isChecked = $(elementId).is(':checked');
                  } else {
                     modData.isChecked = modData.userEnabled;
                  }

                  if (modData.modType == self.mod_type.BASE_MODULE || modData.modType == self.mod_type.ZIP_MODULE || modData.modType == self.mod_type.DIRECTORY_MODULE) {
                     modData.isBaseMod = modData.modType == self.mod_type.BASE_MODULE;
                     if (modData.isBaseMod) {
                        Ember.set(modData, 'flag_description', i18n.t('stonehearth:ui.shell.mods_menu.base_mod'));
                     }
                     self._unmanagedMods[modData.id] = modData;
                  } else if (modData.modType == self.mod_type.WORKSHOP_MODULE) {
                     self._workshopMods[modData.id] = modData;
                  } else if (modData.modType == self.mod_type.STEAM_UPLOADS_MODULE) {
                     self._steamUploadMods[modData.id] = modData;
                  }

                  self._installedModsList[modData.typedId] = modData;
               });

            var unmanagedModsList = radiant.map_to_array(self._unmanagedMods);
            //sort unmanaged by base and required
            self._sortUnmanagedMods(unmanagedModsList);

            //sort workshop by update time? or by name?

            //sort steam upload by name
            var steamUploadsArray = radiant.map_to_array(self._steamUploadMods);
            self._sortModsByName(steamUploadsArray);

            self.set('unmanagedMods', unmanagedModsList);
            self.set('steamUploadMods', steamUploadsArray);
         });
   },

   _multipleModNameEnabled: function() {
      var self = this;
      if (self.get('steamPresent')) {
         var modNameCounts = {};
         radiant.each(self._unmanagedMods, function(i, modData) {
            if (!modNameCounts[modData.name]) {
               modNameCounts[modData.name] = 0;
            }
            if ($('#' + modData.typedId).is(':checked')) {
               modNameCounts[modData.name] = modNameCounts[modData.name] + 1;
            }
         });
         radiant.each(self._workshopDownloads, function(i, modData) {
            if (!modNameCounts[modData.name]) {
               modNameCounts[modData.name] = 0;
            }
            if ($('#' + modData.typedId).is(':checked')) {
               modNameCounts[modData.name] = modNameCounts[modData.name] + 1;
            }
         });
         radiant.each(self._steamUploadMods, function(i, modData) {
            if (!modNameCounts[modData.name]) {
               modNameCounts[modData.name] = 0;
            }
            if ($('#' + modData.typedId).is(':checked')) {
               modNameCounts[modData.name] = modNameCounts[modData.name] + 1;
            }
         });

         var duplicates = radiant.map_to_array(modNameCounts, function(k, v) {
            if (v > 1) {
               return k;
            }
            return false;
         });

         return duplicates;
      }

      return [];
   },

   _setEnabledActions: function() {
      var self = this;

      // unmanaged mods
      self.set('unmanagedEnabledActions', {
         viewTemplatesEnabled: true,
         editTemplatesEnabled: true,
      });

      //steam subscribed items
      self.set('workshopEnabledActions', {
         unsubscribeEnabled: true,
         workshopEnabled: true,
         viewTemplatesEnabled: true,
      });

      //steam uploads
      self.set('myItemsEnabledActions', {
         uploadEnabled: true,
         workshopEnabled: true,
         viewTemplatesEnabled: true,
         editTemplatesEnabled: true,
      });
   },

   _applyMods: function() {
      var self = this;
      var modChanges = [];

      var modsChanged = false;

      // check local unmanaged mods
      radiant.each(self._unmanagedMods, function (key, modInfo) {
         if (!modInfo.unavailable) {
            var modEnabled = $('#' + modInfo.typedId).is(':checked');
            // if enabled state has changed
            if (modEnabled != modInfo.userEnabled) {
               modsChanged = true;
               modChanges.push({
                  name: modInfo.name,
                  modType: modInfo.modType,
                  enabled: modEnabled
               });
            }
         }
      });

      // also check for recently added workshop mods
      radiant.each(self._workshopDownloads, function(key, modInfo) {
         var modEnabled = $('#' + modInfo.typedId).is(':checked');

         // if we just subscribed to this mod and we didn't have it before OR we had the mod before and enabled state has changed
         if (!self._installedModsList[modInfo.typedId] || modEnabled != self._installedModsList[modInfo.typedId].userEnabled) {
            modsChanged = true;
            modChanges.push({
               name: modInfo.name,
               modType: modInfo.modType,
               enabled: modEnabled
            });
         }
      });

      // check steam upload mods
      radiant.each(self._steamUploadMods, function(key, modInfo) {
         if (!modInfo.unavailable) {
            var modEnabled = $('#' + modInfo.typedId).is(':checked');
            // if enabled state has changed
            if (modEnabled != modInfo.userEnabled) {
               modsChanged = true;
               modChanges.push({
                  name: modInfo.name,
                  modType: modInfo.modType,
                  enabled: modEnabled
               });
            }
         }
      });

      // if there were no changes, just go back to the main menu
      if (modChanges.length <= 0) {
         radiant.call('radiant:set_workshop_polling_enabled', false);
         //radiant.call('radiant:client:return_to_main_menu');
         App.navigate('shell/title');
         return;
      }

      var title = i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.title');
      var message = i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.message');
      var buttons = [
         {
            label: i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.accept'),
            click: function () {
               radiant.each(modChanges, function(i, change) {
                  var modTypeString = App.constants.mods.mod_type_string[change.modType];
                  var modConfig = 'mods.' + modTypeString + '.' + change.name + '.enabled';
                  radiant.call('radiant:set_config', modConfig, change.enabled);
               });
               radiant.call('radiant:set_workshop_polling_enabled', false);
               radiant.call('radiant:client:return_to_main_menu');
            }
         },
         {
            label: i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.cancel'),
         }
      ];

      self.addConfirmView(title, message, buttons);
   },

   _sortUnmanagedMods: function(unmanagedModsList) {
      var self = this;
      unmanagedModsList.sort(function(a, b) {
         var priority = a.modType - b.modType;
         if (priority == 0) {
            if (a.status == self.mod_status.REQUIRED && b.status != self.mod_status.REQUIRED) {
               return -1;
            }
            if (a.status != self.mod_status.REQUIRED && b.status == self.mod_status.REQUIRED) {
               return 1;
            }
            if (a.name < b.name) {
               return -1;
            }
            return 1;
         }

         return priority;
      });
   },

   _sortModsByName: function(mods) {
      mods.sort(function (a, b) {
         var aTitle = a.title.toLowerCase();
         var bTitle = b.title.toLowerCase();
         if (aTitle < bTitle) {
            return -1;
         } else if (aTitle > bTitle) {
            return 1;
         } else {
            return 0;
         }
      });
   },

   addConfirmView: function(title, message, buttons) {
      var self = this;
      if (self._confirmView) {
         self._confirmView.destroy();
      }

      self._confirmView = App.shellView.addView(App.StonehearthConfirmView,
         {
            title : title,
            message : message,
            buttons : buttons,
         });
   },

   actions: {
      quitToMainMenu: function() {
         var duplicates = this._multipleModNameEnabled();
         if (duplicates.length > 0) {
            var title = i18n.t('stonehearth:ui.shell.mods_menu.duplicates_dialog.title');

            var message = i18n.t('stonehearth:ui.shell.mods_menu.duplicates_dialog.message');
            for (var i = 0; i < duplicates.length; i++) {
               message += duplicates[i] + "<br>";
            }

            var buttons = [
               {
                  label: i18n.t('stonehearth:ui.shell.mods_menu.duplicates_dialog.ok')
               }
            ];

            this.addConfirmView(title, message, buttons);
         } else {
            this._applyMods();
         }
      },

      openModdingGuide: function() {
         radiant.call('radiant:open_url_external', 'https://stonehearth.github.io/modding_guide/index.html');
      },

      browseWorkshop: function() {
         radiant.call_obj('stonehearth.mod', 'activate_overlay_to_workshop_command');
      },
      createNewMod: function() {
         var self = this;
         if (self._createNewModDeferred) {
            console.log('Create mod already in progress');
            return;
         }

         if (self._createModView) {
            self._createModView.destroy();
         }

         self._createModView = App.shellView.addView(App.StonehearthModCreateView, {
            createdCb: function(success, errorDetails) {
               if (!success) {
                  var title = i18n.t('stonehearth:ui.shell.settings.mods_tab.create_mod_error_dialog.title');
                  var message = i18n.t('stonehearth:ui.shell.settings.mods_tab.create_mod_error_dialog.message', errorDetails);
                  var buttons = [
                     {
                        label: i18n.t('stonehearth:ui.game.common.ok')
                     }
                  ];
                  self.addConfirmView(title, message, buttons);
               }
               self._updateModsList();
            }
         });
      }
   },

   addUploadView: function(modItem, itemDetails, options, onAcceptCb) {
      var self = this;
      if (self._uploadView) {
         self._uploadView.destroy();
      }

      self._uploadView = App.shellView.addView(App.StonehearthModUploadView, {
         modItem: modItem,
         itemDetails: itemDetails,
         buildingTemplates: options.buildingTemplates,
         onAccept: onAcceptCb,
      });
   },

   addEditTemplatesView: function(modItem) {
      var self = this;
      if (self._editTemplatesView) {
         self._editTemplatesView.destroy();
      }

      self._editTemplatesView = App.shellView.addView(App.StonehearthEditTemplateModView, {
         modItem: modItem,
      });
   },

   willDestroyElement: function() {
      if (this._uploadView) {
         this._uploadView.destroy();
         this._uploadView = null;
      }
      if (this._createModView) {
         this._createModView.destroy();
         this._createModView = null;
      }
      if (this._editTemplatesView) {
         this._editTemplatesView.destroy();
         this._editTemplatesView = null;
      }
      if (this._confirmView) {
         this._confirmView.destroy();
         this._confirmView = null;
      }
   }
});


App.StonehearthModListView = App.View.extend({
   templateName: 'stonehearthModList',
   i18nNamespace: 'stonehearth',

   mods: [],
   pageView: null,
   enabledActions: {
      unsubscribeEnabled: false,
      workshopEnabled: false,
      uploadEnabled: false,
      viewTemplatesEnabled: false,
      editTemplatesEnabled: false,
   }
});


App.StonehearthModRowView = App.View.extend({
   templateName: 'stonehearthModRow',
   i18nNamespace: 'stonehearth',

   pageView: null,
   listView: null,
   modItem: null,
   enabledActions: {
      unsubscribeEnabled: false,
      workshopEnabled: false,
      uploadEnabled: false,
      viewTemplatesEnabled: false,
      editTemplatesEnabled: false,
   },

   init: function() {
      this._super();
      var self = this;
      if (self.modItem.state == App.constants.mods.mod_state.DOWNLOADING) {
         self.set("streamInProgress", true);
         self.updateProgress(self.modItem.download_progress);
      }

      self.mod_flag = App.constants.mods.mod_flag;
      self.mod_type = App.constants.mods.mod_type;
      self.mod_state = App.constants.mods.mod_state;
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      // Enable or disable view/edit template buttons based on mod
      // Check for stonehearth mod specifically, because when saving templates in stonehearth or rayyas children,
      // they both use the same building service that writes the local templates into saved_objects/stonehearth/building_templates
      // We also don't currently support zipped mod building templates so disable buttons if so
      var templatesEnabled = (self.modItem.hasBuildingTemplates || self.modItem.name == 'stonehearth') && self.modItem.modType != self.mod_type.ZIP_MODULE;
      if (self.enabledActions.viewTemplatesEnabled) {
         self.set('viewTemplatesEnabled', templatesEnabled);
      }

      if (self.enabledActions.editTemplatesEnabled && self.modItem.modType != self.mod_type.BASE_MODULE && self.modItem.modType != self.mod_type.ZIP_MODULE) {
         self.set('editTemplatesEnabled', templatesEnabled);
      }

      if (self.modItem.modType == App.constants.mods.mod_type.STEAM_UPLOADS_MODULE) {
         radiant.call('radiant:get_steam_item_query_complete_trace')
            .progress(function() {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               self._updateItemDetails();
            });
         self._updateItemDetails();
      }

      Ember.run.scheduleOnce('afterRender', self, function() {
         self.$('.rowButton').tooltipster();
         self.$('.viewTemplates').tooltipster();
      });
   },

   willDestroyElement: function() {
      this._super();
      if (this._confirmView) {
         this._confirmView.destroy();
         this._confirmView = null;
      }
      this.$().find('.tooltipstered').tooltipster('destroy');
   },

   updateProgress: function(percentage) {
      var self = this;
      Ember.run.scheduleOnce('afterRender', self, function() {
         if (self.$('#progress')) {
            self.$('#progress').css("width", percentage / 100 * this.$('#progressbar').width());
         }
      });
   },

   actions: {
      openInWorkshop: function() {
         var self = this;
         radiant.call_obj('stonehearth.mod', 'activate_overlay_to_workshop_item_command', self.modItem.steamFileId);
      },
      openFolder: function() {
         var self = this;
         radiant.call('radiant:client:open_mod_folder', self.modItem.name, self.modItem.modType, self.modItem);
      },
      unsubscribe: function() {
         var self = this;

         var steamFileId = self.modItem.steamFileId;

         var title = i18n.t('stonehearth:ui.shell.mods_menu.unsubscribe_dialog.title');
         var message = i18n.t('stonehearth:ui.shell.mods_menu.unsubscribe_dialog.message');
         var buttons = [
            {
               label: i18n.t('stonehearth:ui.shell.mods_menu.unsubscribe_dialog.accept'),
               click: function () {
                  radiant.call('radiant:unsubscribe_from_workshop_item', steamFileId);
               }
            },
            {
               label: i18n.t('stonehearth:ui.shell.mods_menu.unsubscribe_dialog.cancel')
            }
         ];

         self.pageView.addConfirmView(title, message, buttons);
      },
      toggleTemplates: function() {
         var self = this;
         var showTemplates = !self.get('showTemplates');
         if (showTemplates) {
            self._loadTemplates(function() {
               // Show templates after they've been loaded
               self.set('showTemplates', true);
            });
         } else {
            // Hide templates now
            self.set('showTemplates', false);
         }
      },
      editTemplates: function() {
         var self = this;

         self.pageView.addEditTemplatesView(self.modItem);
         self.set('showTemplates', false);
      },
      openUploadView: function() {
         var self = this;
         var addUploadView = function() {
            var options = {
               buildingTemplates : self.get('buildingTemplates'),
            };
            self.pageView.addUploadView(self.modItem, self.get('itemDetails'), options, function(options) {
               self._onAcceptCb(options);
            });
         };

         if (self.get('editTemplatesEnabled')) {
            self._loadTemplates(addUploadView);
         } else {
            addUploadView();
         }
      }
   },

   _loadTemplates: function(cb) {
      var self = this;
      radiant.call_obj('stonehearth.building', 'load_templates_from_mod', self.modItem.name, self.modItem.modType, self.modItem.steamFileId)
         .done(function(response) {
            var templatesArray = radiant.constructTemplateDataList(response.templates);
            self.set('buildingTemplates', templatesArray);

            if (cb) {
               cb(templatesArray);
            }
         })
         .fail(function(response) {
            console.log('failed to load building templates for ' + self.modItem.name);
         });
   },

   _updateItemDetails: function() {
      var self = this;
      if (radiant.isNonEmptyString(self.modItem.steamFileId)) {
         radiant.call('radiant:get_steam_workshop_item_details', self.modItem.steamFileId)
            .done(function(response) {
               self.set('itemDetails', response.details);
               if (radiant.isNonEmptyString(response.details.title)) {
                  self.set('uploaded', true);
                  self.set('modItem.title', response.details.title);
               }
               if (Object.keys(response.details).length == 0) {
                  self.set('modItem.tooltip', i18n.t('stonehearth:ui.shell.settings.mods_tab.invalid_steam_file'));
                  self.set('modItem.has_error', true);
               } else {
                  self.set('modItem.tooltip', '');
                  self.set('modItem.has_error', false);
               }
            })
            .fail(function(response) {
               // steam is not present
            });
      }
   },

   _steamUploadItemUpdate: function() {
      var self = this;
      if (self.modItem.modType != self.mod_type.STEAM_UPLOADS_MODULE) {
         return;
      }
      var updates = self.get('pageView.steamUploadItemUpdates');
      var steamFileId = self.modItem.steamFileId;
      if (updates && updates[steamFileId]) {
         var status = updates[steamFileId];

         // Do some action based on the item update state
         switch(status.state) {
            case 'succeeded':
               self._onUploadSuccess();
               break;
            case 'updating':
               var percentage = parseInt(status.update_percentage);
               if (!Number.isNaN(percentage) && percentage > 0) {
                  self.updateProgress(status.update_percentage);
               }
               break;
            case 'failed':
               self._onUploadFail(status.error);
               break;
            default:
               console.log('invalid item update state: ' + status.state);
         }
      }
   }.observes('pageView.steamUploadItemUpdates'),

   _workshopItemUpdate: function() {
      var self = this;
      if (self.modItem.modType != self.mod_type.WORKSHOP_MODULE) {
         return;
      }
      var updates = self.get('pageView.workshopItemUpdates');
      var steamFileId = self.modItem.steamFileId;
      var newModItemState = updates && updates[steamFileId];
      if (newModItemState) {
         var wasDownloading = self.modItem.title == i18n.t('stonehearth:ui.shell.settings.mods_tab.loading_namespace');
         self.set('modItem', newModItemState);
         var isDownloading = newModItemState.state == self.mod_state.DOWNLOADING;
         self.set("streamInProgress", isDownloading);

         if (isDownloading) {
            self.updateProgress(self.modItem.download_progress);
         }

         // Make sure title and name observers are notified of changes
         self.set('modItem.title', self.modItem.title);
         self.set('modItem.name', self.modItem.name);

         // Rerender the view if we were downloading so that modItem changes will update in the view
         if (wasDownloading) {
            self.rerender();
         }
      }
   }.observes('pageView.workshopItemUpdates'),

   _onAcceptCb: function(options) {
      var self = this;
      self._showProgressBar(true);

      radiant.call('radiant:update_steam_mod', self.modItem.steamFileId, options)
         .done(function(response) {
            if (response.state == 'submitted' || response.state == 'queued') {
               // do nothing
            } else if (response.error) {
               self._onUploadFail(response.error);
            }
         })
         .fail(function(response) {
            self._onUploadFail(response.error);
         });
   },

   _onUploadFail: function(reason) {
      var self = this;
      var title = i18n.t('stonehearth:ui.shell.settings.mods_tab.upload_error_dialog.title');
      var message = i18n.t('stonehearth:ui.shell.settings.mods_tab.upload_error_dialog.message', {
         modname: self.modItem.name,
         error: i18n.t('stonehearth:ui.shell.mod_upload.errors.' + reason, { modname: self.modItem.name }),
      });
      var buttons = [
         {
            label: i18n.t('stonehearth:ui.game.common.ok')
         }
      ];
      self.pageView.addConfirmView(title, message, buttons);
      self._showProgressBar(false);
   },

   _onUploadSuccess: function() {
      this._showProgressBar(false);
      this._updateItemDetails();
      this.send('openInWorkshop');
   },

   _showProgressBar: function(flag) {
      this.set('streamInProgress', flag);
   }
});