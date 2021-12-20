App.AcePeriodicInteractionView = App.StonehearthBaseZonesModeView.extend({
      templateName: 'acePeriodicInteraction',
      closeOnEsc: true,
   
      components: {
         "stonehearth_ace:periodic_interaction" : {},
      },

   init: function() {
      this._super();

      var self = this;
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self.$('#enabledCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_periodic_interaction_enabled', self.get('uri'), this.checked);
      });

      // tooltips
      App.guiHelper.addTooltip(self.$('#enabledCheckbox'), 'stonehearth_ace:ui.game.periodic_interaction.enabled_description');
      App.guiHelper.addTooltip(self.$('#modeSelectionLabel'), 'stonehearth_ace:ui.game.periodic_interaction.select_mode_description');
   },

   willDestroyElement: function() {
      var self = this;
      if (self._modeSelector) {
         self._modeSelector.find('.tooltipstered').tooltipster('destroy');
         self._modeSelector.empty();
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
               radiant.call('stonehearth_ace:set_periodic_interaction_mode', self.get('uri'), value.key);
            };

            selector = App.guiHelper.createCustomSelector('periodic_interaction_mode', entries, onChanged).container;
            var currentMode = self.get('model.stonehearth_ace:periodic_interaction.current_mode');
            App.guiHelper.setListSelectorValue(selector, uiData[currentMode]);

            self._modeSelector = selector;
            self.$('#modeSelectionList').append(selector);
         }
      }
   }.observes('model.stonehearth_ace:periodic_interaction.ui_data', 'model.stonehearth_ace:periodic_interaction.allow_mode_selection'),
});
