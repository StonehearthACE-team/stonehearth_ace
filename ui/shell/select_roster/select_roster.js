App.StonehearthSelectRosterView = App.View.extend({
   templateName: 'stonehearthSelectRoster',
   i18nNamespace: 'stonehearth',
   classNames: ['flex', 'fullScreen', 'newGameFlowBackground'],
   // Game options (such as peaceful mode, etc.)
   _options: {},
   _components: {
      'citizens' : {
         '*' : {
            'stonehearth:unit_info': {},
            'stonehearth:attributes': {
               'attributes' : {}
            },
         }
      }
   },

   citizenLockedOptions: [],

   init: function() {
      this._super();
      var self = this;
      self._citizensArray = [];
      self._analytics = {
         'game_id': null,
         'total_roster_rerolls': 0,
         'individual_roster_rerolls': 0,
         'appearance_roster_rerolls': 0,
         'total_roster_time': 0
      };
   },

   didInsertElement: function() {
      this._super();
      var self = this;
      self._reembarkOptionSelected = false;
      self._start = Date.now();
      var biome_uri = self._options.biome_src;
      var kingdom_uri = self._options.starting_kingdom;
      self.$('#selectRoster').addClass(biome_uri);
      self.$('#selectRoster').addClass(kingdom_uri);

      self.$('#acceptRosterButton').click(function () {
         if (self._citizensArray.length > 0) {
            self._setTotalTime();
            self._embark();
         }
      });

      self.$('.lockAllButton').tooltipster();

      self.createLockTooltip(self.$('.nameLock.lockImg'), 'name');
      self.createLockTooltip(self.$('#customizeButtons .lockImg'), 'appearance');

      self._generate_citizens(true);
      self.set('selectedViewIndex', 0);

      self._nameInput = new StonehearthInputHelper(self.$('.name'), function (value) {
         radiant.call('stonehearth:set_custom_name', self.get('selected').__self, value);
         var selectedView = self.get('selectedView');
         selectedView.setNameLocked(true);
      });

      self._animateLoading();

      radiant.call('stonehearth:get_reembark_specs_command').done(function (e) {
         self.set('hasReembarkSpecs', Object.keys(e.result).length > 0);
      });
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$().off('click', '#acceptRosterButton');
      this._hideLoading();
   },

   destroy: function() {
      if (this._nameInput) {
         this._nameInput.destroy();
         this._nameInput = null;
      }
      this._super();
   },

   incrementAppearanceRerolls: function() {
      this._analytics.appearance_roster_rerolls += 1;
   },

   incrementIndividualRerolls: function() {
      this._analytics.individual_roster_rerolls += 1;
   },

   _incrementTotalRerolls: function () {
      this._analytics.total_roster_rerolls += 1;
   },

   _setTotalTime: function() {
      this._analytics.total_roster_time = (Date.now() - this._start) / 1000;
   },

   _animateLoading: function() {
      var self = this;
      var loadingElement = self.$('#loadingPeriods');

      var periodsCount = 0;
      var currentPeriods = '';
      self._loadingAnimationInterval = setInterval(function() {
         loadingElement.html(currentPeriods);

         periodsCount++;
         if (periodsCount >= 4) {
            periodsCount = 0;
            currentPeriods = '';
         } else {
            currentPeriods = currentPeriods + '.';
         }

      }, 250);
   },

   _hideLoading: function() {
      var self = this;
      self.$('#loading').hide();
      if (self._loadingAnimationInterval) {
         clearInterval(self._loadingAnimationInterval);
         self._loadingAnimationInterval = null;
      }
   },

   actions: {
      regenerateCitizens: function() {
         var self = this;
         if (self.$('#rerollCitizensText').hasClass('disabled')) {
            return;
         }

         self._resetSelected();
         self._generate_citizens(false);
      },

      showReembarkDialog: function () {
         var self = this;

         if (self._reembarkChoiceView) {
            self._reembarkChoiceView.destroy();
         }

         self._reembarkChoiceView = App.shellView.addView(App.StonehearthReembarkChoiceView, {
            selectedCb: function (reembarkSpecId) {
               radiant.call('stonehearth:get_reembark_specs_command').done(function (e) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }

                  var spec = e.result[reembarkSpecId];
                  self._options.reembark_spec = spec;

                  // First, reset existing citizens.
                  var childViews = self.get('childViews');
                  for (var i = 0; i < childViews.length; ++i) {
                     var citizenView = childViews[i];
                     if (citizenView.get('isFrozen')) {
                        citizenView.setFrozen(false);
                     }
                  }
                  radiant.call_obj('stonehearth.game_creation', 'generate_citizens_command', true)
                     .done(function (e) {
                        if (self.isDestroying || self.isDestroyed) {
                           return;
                        }

                        self.set('citizensArray', radiant.map_to_array(e.citizens));

                        // Generate re-embarking ones if we have selected a crew.
                        if (reembarkSpecId) {
                           radiant.call_obj('stonehearth.game_creation', 'generate_citizens_for_reembark_command', spec)
                              .done(function (e) {
                                 if (self.isDestroying || self.isDestroyed) {
                                    return;
                                 }
                                 var citizenMap = e.citizens;
                                 self._citizensArray = radiant.map_to_array(citizenMap);
                                 self.set('citizensArray', self._citizensArray);
                                 for (var i = 0; i < e.num_reembarked; ++i) {
                                    self.get('childViews')[i].setFrozen(true);
                                 }
                                 self._reembarkOptionSelected = true;
                              });
                        }
                     });
               });
            }
         });
      },

      quitToMainMenu: function() {
         App.stonehearthClient.quitToMainMenu('shellView', this);
      },

      showLoadRosterDialog: function () {
         var self = this;

         if (self._loadRosterView) {
            self._loadRosterView.destroy();
         }

         self._loadRosterView = App.shellView.addView(App.StonehearthStartingRosterChoiceView, {
            selectedCb: function (rosterID) {
               radiant.call('stonehearth_ace:get_starting_rosters_command').done(function (e) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }

                  var spec = e.result[rosterID];

                  if (spec) {
                     // First, reset existing citizens.
                     var childViews = self.get('childViews');
                     for (var i = 0; i < childViews.length; ++i) {
                        var citizenView = childViews[i];
                        if (citizenView.get('isFrozen')) {
                           citizenView.setFrozen(false);
                        }
                     }
                     
                     radiant.call_obj('stonehearth.game_creation', 'generate_citizens_for_reembark_command', spec)
                        .done(function (e) {
                           if (self.isDestroying || self.isDestroyed) {
                              return;
                           }
                           var citizenMap = e.citizens;
                           self._citizensArray = radiant.map_to_array(citizenMap);
                           self.set('citizensArray', self._citizensArray);
                           self._reembarkOptionSelected = false;
                        });
                  }
               });
            }
         });
      },

      showSaveRosterDialog: function () {
         var self = this;

         // if a reembark option was selected, disallow saving this roster, since it wouldn't be saved "properly"
         if (self._reembarkOptionSelected) {
            if (self._confirmView != null && !self._confirmView.isDestroyed) {
               self._confirmView.destroy();
               self._confirmView = null;
            }

            self._confirmView = App.shellView.addView(App.StonehearthConfirmView, {
               title : i18n.t('stonehearth_ace:ui.shell.select_roster.reembark_selected_save_title'),
               message : i18n.t('stonehearth_ace:ui.shell.select_roster.reembark_selected_save_message'),
               buttons : [
                  {
                     id: 'confirm',
                     label: i18n.t('stonehearth:ui.game.common.ok')
                  }
               ]
            });

            return;
         }

         App.shellView.addView(App.StonehearthInputPromptView,
            {
               title: i18n.t('stonehearth_ace:ui.shell.select_roster.save_roster_confirm_title'),
               message: i18n.t('stonehearth_ace:ui.shell.select_roster.save_roster_confirm_message'),
               default_value: i18n.t('stonehearth_ace:ui.shell.select_roster.save_roster_default_name', {number: Math.floor(Math.random() * 999)}),
               buttons: [
                  {
                     label: i18n.t('stonehearth_ace:ui.shell.select_roster.save_roster_confirm_yes'),
                     click: function (inputText) {
                        radiant.call('stonehearth_ace:save_starting_roster_command', inputText, self._citizensArray);
                     }
                  },
                  {
                     label: i18n.t('stonehearth_ace:ui.shell.select_roster.save_roster_confirm_no'),
                     click: function () {
                        // Nothing to do.
                     }
                  }
               ]
            });
      }
   },

   setSelectedCitizen: function(citizen, selectedView, selectedViewIndex) {
      var self = this;
      var existingSelected = self.get('selected');
      if (citizen) {
         var uri = citizen.__self;
         self.set('selected', citizen);
         self.set('selectedView', selectedView);
         self.set('selectedViewIndex', selectedViewIndex)
      }
   },

   setCitizenLockedOptions: function(rosterEntryIndex, options) {
      this.citizenLockedOptions[rosterEntryIndex] = options;
   },

   createLockTooltip: function(element, descriptionKey) {
      var lockTooltipStr = 'stonehearth:ui.data.tooltips.customization_lock.description';
      var selectRosterStr = 'stonehearth:ui.shell.select_roster.';

      element.tooltipster({
         content : i18n.t(lockTooltipStr, {
            customization : i18n.t(selectRosterStr + descriptionKey)
         })
      });
   },

   _generate_citizens: function(initialize) {
      var self = this;

      if (!initialize) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:reroll'} );
      }

      self.$('#rerollCitizensButton').addClass('disabled');
      self.$('#loadCitizensButton').addClass('disabled');
      self.$('#saveCitizensButton').addClass('disabled');

      radiant.call_obj('stonehearth.game_creation', 'generate_citizens_command', initialize, self.citizenLockedOptions)
         .done(function (e) {
            if (!self.$() || self.isDestroying || self.isDestroyed) {
               return;
            }

            if (!initialize) {
               self._incrementTotalRerolls();
            }

            var citizenMap = e.citizens;
            self.$('#rerollCitizensButton').removeClass('disabled');
            self.$('#loadCitizensButton').removeClass('disabled');
            self.$('#saveCitizensButton').removeClass('disabled');
            self._citizensArray = radiant.map_to_array(citizenMap);
            self.set('citizensArray', self._citizensArray);
            if (initialize) {
               self._reembarkOptionSelected = false;
            }

            self._hideLoading();
         })
         .fail(function(e) {
            console.error('generate_citizens failed:', e)
         });
   },

   _embark: function() {
      var self = this;
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'});
      App.navigate('shell/loadout', {_options: self._options, _analytics: self._analytics});
      self.destroy();
   },

   _resetSelected: function () {
      var self = this;
      self.set('selectedView', null);
      self.set('selected', null);
   }
});

// view for an individual roster entity
App.StonehearthCitizenRosterEntryView = App.View.extend({
   tagName: 'div',
   classNames: ['rosterEntry'],
   templateName: 'citizenRosterEntry',
   uriProperty: 'model',

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:attributes': {},
      'stonehearth:traits' : {
         'traits': {
            '*' : {}
         }
      },
      'render_info': {}
   },

   init: function() {
      this.set('lockedOptions', null);
      this._portraitId = 0;
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      var lockTooltipStr = 'stonehearth:ui.data.tooltips.customization_lock.description';
      var selectRosterStr = 'stonehearth:ui.shell.select_roster.';

      self._viewIndex = self.get('index');
      var existingLockedOptions = self.rosterView.citizenLockedOptions[self._viewIndex];
      if (existingLockedOptions) {
         self.set('lockedOptions', existingLockedOptions);
      }

      self._update();
      self._genders = App.constants.population.genders;
      self._default_gender = App.constants.population.DEFAULT_GENDER;
      var editName = this.$().find('.name');
      self._nameInput = new StonehearthInputHelper(editName, function (value) {
            radiant.call('stonehearth:set_custom_name', self._citizenObjectId, value);
            self.setNameLocked(true);
         });

      Ember.run.scheduleOnce('afterRender', self, '_updateStatTooltips');
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      if (this._nameInput) {
         this._nameInput.destroy();
         this._nameInput = null;
      }
      this._super();
   },

   click: function(e) {
      var self = this;
      if (!e.target || !$(e.target).hasClass('rerollCitizenDice')) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });
         self._selectRow(true);
      }
   },

    actions: {
      regenerateCitizenStatsAndAppearance: function() {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         if (self.$('.rerollCitizenDice').hasClass('disabled')) {
            return;
         }

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:reroll'} );

         self.$('.rerollCitizenDice').addClass('disabled');
         var lockedOptions = self._getLockedOptions();

         radiant.call_obj('stonehearth.game_creation', 'regenerate_citizen_stats_and_appearance_command', self._viewIndex, lockedOptions)
            .done(function (e) {
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }
               self.set('uri', e.citizen);

               // if same uri, select row and update view now, since we don't need to wait for model to be updated
               if (self._citizenObjectId == e.citizen) {
                  self._selectRow();
                  self._updateCitizenView(e.citizen);
               } else {
                  self.$().addClass('regenerated');
               }
               self.$('.rerollCitizenDice').removeClass('disabled');
               self.rosterView.incrementIndividualRerolls();
            })
            .fail(function(e) {
               console.error('regenerate citizen failed:', e)
            });
      },

      regenerateCitizenAppearance: function() {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         if (self.$('#rerollAppearanceDice').hasClass('disabled')) {
            return;
         }

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:reroll'} );

         self.$('#rerollAppearanceDice').addClass('disabled');

         radiant.call_obj('stonehearth.customization', 'regenerate_appearance_command', self._citizenObjectId, self._getLockedCustomizations())
            .done(function(e) {
               self._updateCitizenView(self._citizenObjectId);
               self.rosterView.incrementAppearanceRerolls();
               self.$('#rerollAppearanceDice').removeClass('disabled');
            })
            .fail(function(e) {
               console.error('regenerate citizen appearance failed:', e)
            });
      },

      setGender: function(targetGender) {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         var currentGender = self._getCurrentGender();
         if (currentGender == targetGender) {
            return;
         }

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click' });

         radiant.call_obj('stonehearth.game_creation', 'change_gender_command', self._viewIndex, targetGender)
            .done(function(e) {
               self.set('uri', e.citizen);
               self.$().addClass('regenerated');
            })
            .fail(function(e) {
               console.error('change genders command failed:', e)
            });
      },

      changeIndex: function(operator, customizeType) {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         if (self.rosterView.$('#customizeButtons').find('.arrowButton').hasClass('selected')) {
            return;
         }

         self.setCustomizationLocked(customizeType, true);
         self._changeCustomization(operator, customizeType);
      },

      toggleLock: function(type, customizeType) {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         if (type == 'name') {
            var existing = self.get('nameLocked');
            self.setNameLocked(!existing);
         } else if (type == 'customization') {
            var locked = self._isCustomizationLocked(customizeType);
            self.setCustomizationLocked(customizeType, !locked);
         } else {
            console.log('unrecognized argument to toggleLock');
         }
      },

      unlockAllOptions: function() {
         var self = this;
         if (self.get('isFrozen')) {
            return;
         }

         self.set('lockedOptions', null);
         self.notifyPropertyChange('lockedOptions');
      },

      lockAllOptions: function() {
         var self = this;
         self.setNameLocked(true);
         self.setCustomizationLocked('head_hair', true);
         self.setCustomizationLocked('face_hair', true);
         self.setCustomizationLocked('hair_color', true);
         self.setCustomizationLocked('skin_color', true);
      }
    },

    isFrozen: function () {
       return this.get('lockedOptions') && this.get('lockedOptions').frozen;
    }.property('hiddenCustomizations', 'lockedOptions'),

    setFrozen: function (isFrozen) {
       var self = this;
       if (isFrozen) {
          self.setNameLocked(true);
          self.setCustomizationLocked('head_hair', true);
          self.setCustomizationLocked('face_hair', true);
          self.setCustomizationLocked('hair_color', true);
          self.setCustomizationLocked('skin_color', true);
          var lockedOptions = self.get('lockedOptions');
          lockedOptions.frozen = true;
          self.set('lockedOptions', lockedOptions);
          self.notifyPropertyChange('lockedOptions');
       } else {
          self.set('lockedOptions', null);
          self.notifyPropertyChange('lockedOptions');
       }
    },

   setCustomizationHidden: function(customizeType, bool) {
      var hiddenCustomizations = this.get('hiddenCustomizations') || {};
      hiddenCustomizations[customizeType] = bool;
      this.set('hiddenCustomizations', hiddenCustomizations);
      this.notifyPropertyChange('hiddenCustomizations');
   },

   setCustomizationLocked: function(customizeType, bool) {
      var lockedOptions = this.get('lockedOptions') || {};
      if (!lockedOptions.customizations) {
         lockedOptions.customizations = {};
      }
      lockedOptions.customizations[customizeType] = bool;
      this.set('lockedOptions', lockedOptions);
      this.notifyPropertyChange('lockedOptions');
   },

   setNameLocked: function(bool) {
      var lockedOptions = this.get('lockedOptions') || {};
      lockedOptions.name = bool;
      this.set('lockedOptions', lockedOptions);
      this.notifyPropertyChange('lockedOptions');
   },

   _getLockedOptions: function() {
      if (this.get('anyOptionLocked')) {
         return this.get('lockedOptions');
      }
   },

   _updateCustomizationIndices: function(citizen) {
      var self = this;
      radiant.call_obj('stonehearth.customization', 'get_and_update_customization_indices_command', citizen)
         .done(function (response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('styleIndices', response.category_indices);
            self.set('styleIndexMap', response.index_map);
            radiant.each(response.index_map, function (category, _) {
               var index = response.category_indices[category];
               self._updateCustomizationButton(category, index);
            });
         });
   },

   _updateCustomizationButton: function(category, index) {
      var self = this;
      // hide button for this category if we have no options for it
      var hide = !index;
      self.setCustomizationHidden(category, hide);
      // update index displayed on button
      self.set(category + '_index', index);
   },

   _changeCustomization: function(operator, customizeType) {
      var self = this;
      var styleIndices = self.get('styleIndices');
      var styleIndexMap = self.get('styleIndexMap');

      if (styleIndices && styleIndexMap) {
         var currentIndex = styleIndices[customizeType];
         var data = styleIndexMap[customizeType];

         if (!currentIndex || !data) {
            return; // entity has no options for this customization type
         }

         if (data.length) {
            var newIndex = self._getNextIndex(currentIndex, data.length, operator);

            self.rosterView.$('#customizeButtons').find('.arrowButton').addClass('selected');
            radiant.call_obj('stonehearth.customization', 'change_customization_command', self._citizenObjectId, customizeType, newIndex)
               .done(function(response) {
                  // update style indices and index
                  var currentIndices = self.get('styleIndices');
                  currentIndices[customizeType] = newIndex;
                  self.set(customizeType + '_index', newIndex);
                  self.rosterView.$('#customizeButtons').find('.arrowButton').removeClass('selected');
                  self._updatePortrait();
               })
               .fail(function(response) {
                  console.log('change_customization_command failed. ' + response);
               });
         }
      }
   },

   _getNextIndex: function(index, max, operator) {
      var newIndex;
      if (operator == 'increment') {
         newIndex = (index % max) + 1; // 1-based indexing for lua
      } else if (operator == 'decrement') {
         if (index - 1 <= 0) {
            newIndex = max;
         } else {
            newIndex = (index + max - 1) % max;
         }
      } else {
         console.log('invalid operator ' + operator);
      }

      return newIndex;
   },

   _updatePortrait: function() {
      var self = this;
      // add a dummy parameter portraitId so ember will rerender the portrait even if the entity stays the same (their appearance may have changed)
      self.set('portrait', '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + self._citizenObjectId + '&portraitId=' + self._portraitId);
      self._portraitId += 1;
   },

   _updateStatTooltips: function() {
      var self = this;

      var stats = self.$('.stat')
      if (stats) {
         stats.each(function(){
            var attrib_name = $(this).attr('id');
            var tooltipString = App.tooltipHelper.getTooltip(attrib_name);
            $(this).tooltipster({content: $(tooltipString)});
         });
      }
   },

   _getCurrentGender: function() {
      return this.get('model.render_info.model_variant') || this._default_gender;
   },

   _onLockedOptionsChanged: function() {
      var self = this;
      var lockedOptions = self._getLockedOptions();
      self.rosterView.setCitizenLockedOptions(self._viewIndex, lockedOptions);

      // update lock tooltip based on whether name and/or appearance have been locked
      if (lockedOptions) {
         self.$().find('.lockImg.tooltipstered').tooltipster('destroy');
         var nameLocked = self._isNameLocked();
         var customizationLocked = self._isAnyCustomizationLocked();
         var tooltipKey = '';
         if (nameLocked && customizationLocked) {
            tooltipKey = 'name_and_appearance';
         } else if (nameLocked) {
            tooltipKey = 'name';
         } else if (customizationLocked) {
            tooltipKey = 'appearance';
         }

         self.rosterView.createLockTooltip(self.$('.lockImg'), tooltipKey);
      }
   }.observes('lockedOptions'),

   _onNameChanged: function() {
      var unit_name = i18n.t(this.get('model.stonehearth:unit_info.display_name'), {self: this.get('model')});
      this.set('model.unit_name', unit_name);
   }.observes('model.stonehearth:unit_info'),

   _selectRow: function() {
      var self = this;
      var selected = self.$().hasClass('selected'); // Is this row already selected?
      if (!selected) {
         self.rosterView.$('.rosterEntry').removeClass('selected'); // Unselect everything in the parent view
         self.$().addClass('selected');
      }

      self.rosterView.setSelectedCitizen(self.get('model'), self, self._viewIndex);
   },

   _update: function() {
      var self = this;
      var citizenData = self.get('model');
      if (self.$() && citizenData) {
         self._citizenObjectId = citizenData.__self;
         self._updateCitizenView(self._citizenObjectId);
         if (self.$().hasClass('regenerated')) {
            self.$().removeClass('regenerated');
            self._selectRow();
         } else if (!self.$().hasClass('selected')) {
            if (self._viewIndex == self.rosterView.get('selectedViewIndex')) {
               self._selectRow();
            }
         }
      }
   }.observes('model'),

   _updateCitizenView: function(citizen) {
      var self = this;

      if (citizen) {
         self._updatePortrait();
         self._updateCustomizationIndices(citizen);
      }
   },

   _buildTraitsArray: function() {
      var traits = [];
      var traitMap = this.get('model.stonehearth:traits.traits');

      if (traitMap) {
         traits = radiant.map_to_array(traitMap);
         traits.sort(function(a, b){
            var aUri = a.uri;
            var bUri = b.uri;
            var n = aUri.localeCompare(bUri);
            return n;
         });
      }

      this.set('traits', traits);
   }.observes('model.stonehearth:traits'),

   _isCustomizationLocked: function(customizeType) {
      return this._getLockedCustomizations()[customizeType];
   },

   _isNameLocked: function() {
      var lockedOptions = this.get('lockedOptions');
      return lockedOptions && lockedOptions.name;
   },

   _isAnyCustomizationLocked: function() {
      var self = this;
      var lockedCustomizations = self._getLockedCustomizations();
      var hasLockedCustomization = false;
      radiant.each(lockedCustomizations, function(customizeType, isLocked) {
         if (isLocked) {
            // only counts as locked if customization type is not hidden
            if (!self._isCustomizationHidden(customizeType)) {
               hasLockedCustomization = true;
               return false;
            }
         }
      });

      return hasLockedCustomization;
   },

   _isCustomizationHidden: function(customizeType) {
      var hidden = this.get('hiddenCustomizations');
      return hidden && hidden[customizeType];
   },

   _getLockedCustomizations: function() {
      var lockedOptions = this.get('lockedOptions');
      return (lockedOptions && lockedOptions.customizations) || {};
   },

    // properties that control gender, and customization locking / hiding
   male: function() {
      var gender = this._getCurrentGender();
      if (gender == this._genders.male) {
         return 'selected';
      };
   }.property('model.render_info'),

   female: function() {
      var gender = this._getCurrentGender();
      if (gender == this._genders.female) {
         return 'selected';
      };
   }.property('model.render_info'),

   hairStyleLocked: function() {
      var self = this;
      if (self._isCustomizationHidden('head_hair')) {
         return 'hidden';
      }

      if (self._isCustomizationLocked('head_hair')) {
         return 'locked';
      }
   }.property('hiddenCustomizations', 'lockedOptions'),

   faceHairLocked: function() {
      var self = this;
      if (self._isCustomizationHidden('face_hair')) {
         return 'hidden';
      }

      if (self._isCustomizationLocked('face_hair')) {
         return 'locked';
      }
   }.property('hiddenCustomizations', 'lockedOptions'),

   skinColorLocked: function() {
      var self = this;
      if (self._isCustomizationHidden('skin_color')) {
         return 'hidden';
      }

      if (self._isCustomizationLocked('skin_color')) {
         return 'locked';
      }
   }.property('hiddenCustomizations', 'lockedOptions'),

   hairColorLocked: function() {
      var self = this;
      if (self._isCustomizationHidden('hair_color')) {
         return 'hidden';
      }

      if (self._isCustomizationLocked('hair_color')) {
         return 'locked';
      }
   }.property('hiddenCustomizations', 'lockedOptions'),

   nameLocked: function() {
      return this._isNameLocked();
   }.property('lockedOptions'),

   // check if any options are locked (name, appearance customizations)
   anyOptionLocked: function() {
      var self = this;
      var lockedOptions = self.get('lockedOptions');
      if (lockedOptions) {
         if (self._isNameLocked()) {
            return true;
         }

         if (self._isAnyCustomizationLocked()) {
            return true;
         }
      }

      return false;
   }.property('hiddenCustomizations', 'lockedOptions'),

   allOptionsLocked: function() {
      return this.get('nameLocked') &&
             this.get('hairStyleLocked') &&
             this.get('faceHairLocked') &&
             this.get('skinColorLocked') &&
             this.get('hairColorLocked');
   }.property('hiddenCustomizations', 'lockedOptions')

});


App.StonehearthReembarkChoiceView = App.View.extend({
   templateName: 'stonehearthReembarkChoice',
   classNames: [],
   selectedCb: null,
   _components: {},

   init: function() {
      this._super();
      var self = this;
      
      radiant.call('stonehearth:get_reembark_specs_command').done(function (e) {
         var specs = [];
         radiant.each(e.result, function (id, spec) {
            spec.id = id;

            // Give citizens job icons.
            radiant.each(spec.citizens, function (_, citizen) {
               var jobInfo = App.jobConstants[citizen.current_job];
               if (jobInfo) {
                  citizen.job_icon = jobInfo.description.icon;
               }
            });

            // Give items their icons.
            spec.item_icons = [];
            radiant.each(spec.items, function (_, item) {
               for (var i = 0; i < item.count; ++i) {
                  var catalog_data = App.catalog.getCatalogData(item.uri);
                  if (catalog_data) {
                     spec.item_icons.push(catalog_data.icon);
                  }
                  // TODO: Show an error icon for invalid items (e.g. from unavailable mods).
               }
            });

            // Sum up recipes.
            spec.recipeCount = 0;
            radiant.each(spec.recipes, function (_, recipe_keys) {
               spec.recipeCount += recipe_keys.length;
            });

            specs.push(spec);
         });
         specs.sort((a, b) => a.name < b.name);
         self.set('reembarkSpecs', e.result);
         self.set('reembarkSpecsArray', specs);
      });
   },

   didInsertElement: function () {
      var self = this;

      self.$().on('click', '.row', function () {
         if ($(this).hasClass('selected')) {
            $(this).removeClass('selected');
         } else {
            self.$('.row').removeClass('selected');
            $(this).addClass('selected');
         }
      });
   },

   willDestroyElement: function () {
      var self = this;

      self.$().off('click', '.row');
   },

   actions: {
      delete: function () {
         var self = this;
         var specId = this._getSelectedSpec();
         
         App.shellView.addView(App.StonehearthConfirmView,
            {
               title: i18n.t('stonehearth:ui.shell.select_roster.delete_crew_confirm_title'),
               message: i18n.t('stonehearth:ui.shell.select_roster.delete_crew_confirm_message'),
               buttons: [
                  {
                     label: i18n.t('stonehearth:ui.shell.select_roster.delete_crew_confirm_yes'),
                     click: function () {
                        radiant.call('stonehearth:delete_reembark_spec_command', specId).done(function (e) {
                           self.set('reembarkSpecsArray', self.get('reembarkSpecsArray').filter(function(s) { return s.id != specId; }));
                        });
                     }
                  },
                  {
                     label: i18n.t('stonehearth:ui.shell.select_roster.delete_crew_confirm_no'),
                     click: function () {
                        // Nothing to do.
                     }
                  }
               ]
            });
      },
      select: function () {
         if (this.selectedCb) {
            this.selectedCb(this._getSelectedSpec());
            this.destroy();
         }
      },
      cancel: function () {
         this.destroy();
      }
   },

   _getSelectedSpec: function () {
      var row = this.$('.row.selected');
      if (!row) {
         return null;
      }
      return row.attr('data-id');
   },
});

App.StonehearthStartingRosterChoiceView = App.View.extend({
   templateName: 'stonehearthStartingRosterChoice',
   classNames: [],
   selectedCb: null,
   _components: {},

   init: function() {
      this._super();
      var self = this;
      
      radiant.call('stonehearth_ace:get_starting_rosters_command').done(function (e) {
         var rosters = [];
         radiant.each(e.result, function (id, roster) {
            roster.id = id;
            rosters.push(roster);
         });
         rosters.sort(function(a, b) {
            if (a.invalid_traits === b.invalid_traits) {
               return a.name.localeCompare(b.name);
            }
            else if (a.invalid_traits) {
               return 1;
            }
            else {
               return -1;
            }
         });
         self.set('startingRosters', e.result);
         self.set('startingRostersArray', rosters);

         Ember.run.scheduleOnce('afterRender', self, '_updateInvalidTraitTooltips');
      });
   },

   didInsertElement: function () {
      var self = this;

      self.$().on('click', '.row', function () {
         if ($(this).hasClass('selected')) {
            $(this).removeClass('selected');
            self.$('#deleteStartingRosterButton > button').addClass('disabled');
            self.$('#selectStartingRosterButton > button').addClass('disabled');
         } else {
            self.$('.row').removeClass('selected');
            $(this).addClass('selected');
            self.$('#deleteStartingRosterButton > button').removeClass('disabled');
         }

         // if the newly selected row is invalid, disable the select button, and vice-versa
         if ($(this).hasClass('hasInvalidTraits'))
         {
            self.$('#selectStartingRosterButton > button').addClass('disabled');
         } else {
            self.$('#selectStartingRosterButton > button').removeClass('disabled');
         }
      });
   },

   _updateInvalidTraitTooltips: function() {
      var self = this;

      var invalidTraits = self.$('.row.hasInvalidTraits');
      if (invalidTraits) {
         invalidTraits.each(function(){
            var tooltipString = App.tooltipHelper.createTooltip(
               i18n.t('stonehearth_ace:ui.shell.select_roster.invalid_traits_title'),
               i18n.t('stonehearth_ace:ui.shell.select_roster.invalid_traits_description')
            );
            $(this).tooltipster({content: $(tooltipString)});
         });
      }
   },

   willDestroyElement: function () {
      var self = this;

      self.$().off('click', '.row');
   },

   actions: {
      delete: function () {
         var self = this;
         var rosterId = this._getSelectedRoster();
         if (!rosterId) {
            return;
         }

         App.shellView.addView(App.StonehearthConfirmView,
            {
               title: i18n.t('stonehearth_ace:ui.shell.select_roster.delete_roster_confirm_title'),
               message: i18n.t('stonehearth_ace:ui.shell.select_roster.delete_roster_confirm_message'),
               buttons: [
                  {
                     label: i18n.t('stonehearth_ace:ui.shell.select_roster.delete_roster_confirm_yes'),
                     click: function () {
                        radiant.call('stonehearth_ace:delete_starting_roster_command', rosterId).done(function (e) {
                           self.set('startingRostersArray', self.get('startingRostersArray').filter(function(s) { return s.id != rosterId; }));
                        });
                     }
                  },
                  {
                     label: i18n.t('stonehearth_ace:ui.shell.select_roster.delete_roster_confirm_no'),
                     click: function () {
                        // Nothing to do.
                     }
                  }
               ]
            });
      },
      select: function () {
         var rosterId = this._getSelectedRoster();

         if (rosterId && this.selectedCb) {
            this.selectedCb(this._getSelectedRoster());
            this.destroy();
         }
      },
      cancel: function () {
         this.destroy();
      }
   },

   _getSelectedRoster: function () {
      var row = this.$('.row.selected');
      if (!row) {
         return null;
      }
      return row.attr('data-id');
   },
});