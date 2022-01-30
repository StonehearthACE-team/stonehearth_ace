App.AcePeriodicInteractionView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'acePeriodicInteraction',
   closeOnEsc: true,

   components: {
      "stonehearth:ownable_object" : {},
      "stonehearth_ace:periodic_interaction" : {},
   },

   _peoplePicker: null,

   init: function() {
      this._super();

      var self = this;
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self.$('#enabledCheckbox').change(function() {
         var component = self.get('model.stonehearth_ace:periodic_interaction');
         radiant.call_obj(component && component.__self, 'set_enabled_command', this.checked);
      });

      // tooltips
      App.guiHelper.addTooltip(self.$('#enabledDiv'), 'stonehearth_ace:ui.game.periodic_interaction.enabled_description');
      App.guiHelper.addTooltip(self.$('#assignOwnerButton'), 'stonehearth:data.commands.change_owner.description');
      App.guiHelper.addTooltip(self.$('#modeSelectionLabel'), 'stonehearth_ace:ui.game.periodic_interaction.select_mode_description');
   },

   willDestroyElement: function() {
      var self = this;
      if (self._modeSelector) {
         self._modeSelector.find('.tooltipstered').tooltipster('destroy');
         self._modeSelector.empty();
      }
      if (self._peoplePicker) {
         self._peoplePicker.destroy();
         self._peoplePicker = null;
      }

      this._super();
   },

   _uiDataChanged: function() {
      
   }.observes('model.stonehearth_ace:periodic_interaction.ui_data'),

   _selectionChanged: function() {
      var self = this;
      var enabled = self.get('model.stonehearth_ace:periodic_interaction.enabled');

      self.$('#enabledCheckbox').prop('checked', enabled);
   }.observes('model.stonehearth_ace:periodic_interaction.enabled'),

   _updateSelectedMode: function() {
      var self = this;
      var uiData = self.get('model.stonehearth_ace:periodic_interaction.ui_data');
      var currentMode = self.get('model.stonehearth_ace:periodic_interaction.current_mode');

      if (uiData && currentMode && uiData[currentMode]) {
         var uiEntry = uiData[currentMode];
         self.set('currentModeName', uiEntry.display_name);
         self.set('currentModeDescription', uiEntry.description);
      }
   }.observes('model.stonehearth_ace:periodic_interaction.current_mode'),

   _updateModeSelection: function() {
      var self = this;
      self._super();

      // add custom list selector
      var selector = self._modeSelector;
      if (selector) {
         selector.find('tooltipster').tooltipster('destroy');
         selector.remove();
      }

      var allowModeSelection = self.get('model.stonehearth_ace:periodic_interaction.allow_mode_selection');
      var uiData = self.get('model.stonehearth_ace:periodic_interaction.ui_data');

      if (uiData) {
         var entries = radiant.map_to_array(uiData, function(k, v) {
            v.key = k;
         });

         // only bother showing the dropdown both if it's allowed and if there's more than one entry
         var showModeSelection = allowModeSelection && entries.length > 1;
         self.set('showModeSelection', showModeSelection);

         if (showModeSelection) {
            var onChanged = function (key, value) {
               var component = self.get('model.stonehearth_ace:periodic_interaction');
               radiant.call_obj(component && component.__self, 'select_mode_command', value.key);
            };

            selector = App.guiHelper.createCustomSelector('periodic_interaction_mode', entries, onChanged).container;
            var currentMode = self.get('model.stonehearth_ace:periodic_interaction.current_mode');
            App.guiHelper.setListSelectorValue(selector, uiData[currentMode]);

            self._modeSelector = selector;
            self._updateJobLevelEligibilityForModes(entries);
            self.$('#modeSelectionList').append(selector);
         }
      }
   }.observes('model.stonehearth_ace:periodic_interaction.ui_data', 'model.stonehearth_ace:periodic_interaction.allow_mode_selection'),

   _updateJobLevelEligibilityForModes: function(uiDataArr) {
      var self = this;
      var selector = self._modeSelector;
      if (selector) {
         uiDataArr.forEach(modeData => {
            var $divs = selector.find('[data-key="' + modeData.key + '"]');
            if (modeData.has_eligible_job === true) {
               $divs.removeClass('has-ineligible-job');
            } else if (modeData.has_eligible_job === false) {
               $divs.addClass('has-ineligible-job');
            }
         });
      }
   },

   _ownerAssignmentCallback: function(object, newOwner) {
      if (object) {
         radiant.call_obj(object.get('stonehearth_ace:periodic_interaction').__self, 'set_owner_command', newOwner && newOwner.__self);
      }
   },

   _canBeOwnerCallback: function(object, person) {
      if (!object) {
         return false;
      }

      if (object.get('player_id') != person.get('player_id')) {
         // Not in the same faction1
         return false;
      }

      return true;
   },

   _ownerSortFunction: function(object, people) {
      var currentOwner = object.get('stonehearth_ace:periodic_interaction.current_owner');
      if (currentOwner) {
         for (var i=0; i<people.length; ++i) {
            var person = people[i];
            if (person === currentOwner) {
               people[i] = people[0];
               people[0] = person;
               break;
            }
         }
      }

      return people;
   },

   _getOwnershipTooltip: function(object, person) {
      var currentOwner = object.get('stonehearth_ace:periodic_interaction.current_owner');
      var personUri = person.__self;
      if (currentOwner === personUri) {
         // this is the current owner of this object
         return "stonehearth:ui.game.people_picker.ownership_current_owner_tooltip";
      }

      return null;
   },

   // all periodic interaction owners are citizen owners
   _hasCitizenOwner: function(object) {
      var currentOwner = object.get('stonehearth_ace:periodic_interaction.current_owner');
      return currentOwner != null;
   },

   _noReservation: function(object) {
      var currentOwner = object.get('stonehearth_ace:periodic_interaction.current_owner');
      if (!currentOwner) {
         return "stonehearth_ace:ui.game.people_picker.already_no_owner";
      }

      return null;
   },

   actions: {
      showAssignOwner: function() {
         var self = this;
         var entity = self.get('uri');
         var piComp = self.get('model.stonehearth_ace:periodic_interaction');
   
         if (!self._peoplePicker || self._peoplePicker.isDestroyed) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} );
            radiant.call_obj(piComp, 'get_valid_users_command')
            .done(function(result) {
               var filterFn = function(object, person) {
                  if (Array.isArray(result.users)) {
                     var isValid = result.users.includes(person.__self);
                     return isValid && self._canBeOwnerCallback(object, person);
                  }
                  else {
                     return false;
                  }
               };
               
               self._peoplePicker = App.gameView.addView(App.StonehearthPeoplePickerView, {
                     uri: entity,
                     onlyShowCitizens: true,
                     callback: self._ownerAssignmentCallback,
                     personFilter: filterFn,
                     tooltipGenerator: self._getOwnershipTooltip,
                     sortFunction: self._ownerSortFunction,
                     hasCitizenOwner: self._hasCitizenOwner,
                     noOwnerCallback: self._ownerAssignmentCallback,
                     noOwnerTooltip: self._noReservation,
                  });
            });
         } else {
            self._peoplePicker.destroy();
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:jobs_close' });
            self._peoplePicker = null;
         }
      }
   }
});
