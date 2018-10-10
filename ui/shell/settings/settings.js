$(top).on('stonehearthReady', function(cc) {
   App.SettingsView.reopen({
      didInsertElement: function() {
         this._super();

         // Adding a toggle button to turn on/off the Auto Craft Recipe Dependencies feature
         this.autoCraftDiv = this._addSimpleGameplaySetting(
            {type: 'checkbox', id: 'opt_autoCraftRecipeDependencies'},
            {display_name: "stonehearth_ace:ui.shell.settings.gameplayTab.auto_craft_recipe_dependencies",
               description: "stonehearth_ace:ui.shell.settings.gameplayTab.auto_craft_recipe_dependencies_description"},
               5);

         // adding a toggle button for whether auto-harvest is automatically enabled for anything that doesn't specify a setting for it
         this.autoEnableAutoHarvest = this._addSimpleGameplaySetting(
            {type: 'checkbox', id: 'opt_autoHarvestAfterFirstHarvest'},
            {display_name: "stonehearth_ace:ui.shell.settings.gameplayTab.auto_harvest_enabled",
               description: "stonehearth_ace:ui.shell.settings.gameplayTab.auto_harvest_enabled_description"},
               6);
      },

      _updateGameplayTabPage: function() {
         this._super();

         var self = this;
         radiant.call('radiant:get_config', 'mods.stonehearth_ace')
            .done(function(response) {
               var aceOptions = response['mods.stonehearth_ace'] || {};
               if (aceOptions) {
                  self.autoCraftDiv.childNodes[0].checked = aceOptions.auto_craft_recipe_dependencies === false ? false : true;
                  self.autoEnableAutoHarvest.childNodes[0].checked = ~~aceOptions.auto_enable_auto_harvest;
               } else {
                  self.autoCraftDiv.childNodes[0].checked = true;
                  self.autoEnableAutoHarvest.childNodes[0].checked = false;
               }
               var oldOpts = self.get('oldGameplayOptions');
               oldOpts['auto_craft_recipe_dependencies'] = aceOptions.auto_craft_recipe_dependencies;
               oldOpts['auto_enable_auto_harvest'] = aceOptions.auto_enable_auto_harvest;
               self.set('oldGameplayOptions', oldOpts);
            });
      },

      _getGameplayConfig: function() {
         var res = this._super();
         res['auto_craft_recipe_dependencies'] = $('#opt_autoCraftRecipeDependencies').is(':checked');
         res['auto_enable_auto_harvest'] = $('#opt_autoHarvestAfterFirstHarvest').is(':checked');
         return res;
      },

      _applyGameplaySettings: function() {
         this._super();

         radiant.call('radiant:set_config', 'mods.stonehearth_ace.auto_craft_recipe_dependencies', $('#opt_autoCraftRecipeDependencies').is(':checked'));
         var auto_harvest = $('#opt_autoHarvestAfterFirstHarvest').is(':checked');
         radiant.call('radiant:set_config', 'mods.stonehearth_ace.auto_enable_auto_harvest', auto_harvest);
         radiant.call('stonehearth_ace:update_auto_harvest_setting', auto_harvest);
      },

      // Adds a single gameplay setting.
      // Not to be used for more complex settings, or for other setting tabs such as sound.
      _addSimpleGameplaySetting: function(inputData, labelData, position) {
         if (!position) position = 0;
         $gameplayTab = $('#gameplayTab');
         var newDiv = null;
         if ($gameplayTab) {
            newDiv = document.createElement('div');
            newDiv.classList.add('setting');
            var input = document.createElement('input');
            input.type = inputData.type;
            input.id = inputData.id;
            var label = document.createElement('label');
            label.setAttribute('for', inputData.id);
            this._addTooltip(label, labelData.description);
            label.innerHTML = i18n.t(labelData.display_name);
            newDiv.appendChild(input);
            newDiv.appendChild(label);
            $gameplayTab[0].insertBefore(newDiv, $gameplayTab[0].childNodes[6+2*position])
         }
         return newDiv;
      },

      _addTooltip: function(itemEl, title) {
         var tooltip = App.tooltipHelper.createTooltip("", i18n.t(title), "");
         $(itemEl).tooltipster({ content: $(tooltip) });
      }
   });
});
