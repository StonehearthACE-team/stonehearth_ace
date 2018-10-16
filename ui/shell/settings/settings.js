$(top).on('stonehearthReady', function(cc) {
   App.SettingsView.reopen({
      didInsertElement: function() {
         var self = this;
         self._super();

         $gameplayTab = $('#gameplayTab');
         if(!$gameplayTab || !$gameplayTab[0]) return;

         // remove the useless header part of it
         for(var i=0; i<3; i++) {
            $gameplayTab[0].children[0].remove();
         }

         radiant.call('radiant:get_all_mods')
            .done(function(mods) {
               var _mods = {};
               radiant.each(mods, function(_, modData) {
                  _mods[modData.name] = modData;
               });
               self._mods = _mods;

               // create collapsible container for [stonehearth] settings and move them into it
               var parentElements = self._createGameplayDivForMod('stonehearth');
               $gameplayTab.contents().appendTo(parentElements.section);
               var accordion = document.createElement('div');
               accordion.id = 'modSettingsAccordion';
               accordion.appendChild(parentElements.header);
               accordion.appendChild(parentElements.section);
               $gameplayTab[0].appendChild(accordion);

               // load up settings from client state (only care about mod settings, not [stonehearth] overrides)
               radiant.call('stonehearth_ace:get_all_client_gameplay_settings_command')
                  .done(function(response){
                     var settings = response.settings;
                     self._settings = settings;

                     // create collapsible containers for other mods' settings and create their settings within them
                     radiant.each(settings, function(mod, modSettings) {
                        if(mod != 'stonehearth') {
                           parentElements = self._createGameplayDivForMod(mod, modSettings);
                           accordion.appendChild(parentElements.header);
                           accordion.appendChild(parentElements.section);
                        }
                     });

                     $(accordion).accordion({
                        heightStyle: "content"
                     });

                     self._updateModifiedGameplayTabPage();
                  });
            });
         
            return;
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

      _updateModifiedGameplayTabPage: function() {
         var self = this;
         
         radiant.call('radiant:get_config', 'mods')
            .done(function(response) {
               var mods = response.mods || {};
               radiant.each(mods, function(mod, settings) {
                  var _settings = self._settings[mod];
                  if(_settings) {
                     radiant.each(settings, function(name, value) {
                        var _setting = _settings[name];
                        if(_setting) {
                           _setting.value = value;
                           if(mod != 'stonehearth' && _setting.setValue) {
                              _setting.setValue(value);
                           }
                        }
                     });
                  }
               });
            });
      },

      _updateGameplayTabPage: function() {
         var self = this;
         this._super();

         return;
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
         var self = this;
         var result = self._super();

         radiant.each(self._settings, function(mod, modSettings){
            if(mod != 'stonehearth') {
               radiant.each(modSettings, function(name, setting){
                  if(setting.getValue) {
                     result[mod+':'+name] = setting.getValue();
                  }
               });
            }
         });

         return result;
      },

      _applyGameplaySettings: function() {
         var self = this;
         self._super();

         radiant.each(self._settings, function(mod, modSettings){
            if(mod != 'stonehearth') {
               radiant.each(modSettings, function(name, setting){
                  if(setting.getValue) {
                     var value = setting.getValue();
                     radiant.call('radiant:set_config', 'mods.'+mod+'.'+name, value);
                     if(setting.on_change) {
                        var call = setting.on_change.call;
                        if(call) {
                           radiant.call(mod+':'+call, value);
                        }
                     }
                  }
               });
            }
         });

         radiant.call('stonehearth_ace:set_client_gameplay_settings_command', self._settings);
      },

      _getGameplayConfig_1: function() {
         var res = this._super();
         res['auto_craft_recipe_dependencies'] = $('#opt_autoCraftRecipeDependencies').is(':checked');
         res['auto_enable_auto_harvest'] = $('#opt_autoHarvestAfterFirstHarvest').is(':checked');
         return res;
      },

      _applyGameplaySettings_1: function() {
         this._super();

         radiant.call('radiant:set_config', 'mods.stonehearth_ace.auto_craft_recipe_dependencies', $('#opt_autoCraftRecipeDependencies').is(':checked'));
         var auto_harvest = $('#opt_autoHarvestAfterFirstHarvest').is(':checked');
         radiant.call('radiant:set_config', 'mods.stonehearth_ace.auto_enable_auto_harvest', auto_harvest);
         radiant.call('stonehearth_ace:update_auto_harvest_setting', auto_harvest);
      },

      _createGameplayDivForMod: function(mod, settings) {
         var self = this;
         var modData = self._mods && self._mods[mod];
         if(modData) {
            // create the jQuery accordian structure
            var title = modData.title;
            var newHeader = document.createElement('h3');
            newHeader.classList.add('modHeader');
            newHeader.innerText = title;
            var newSection = document.createElement('div');
            newSection.classList.add('modSettings');

            if(settings) {
               // if there are actually settings, create the elements for them
               radiant.each(settings, function(name, setting) {
                  var element = self._createGameplaySettingElements(name, setting);
                  if(element) {
                     newSection.appendChild(element);
                  }
               });
            }

            return {header: newHeader, section: newSection};
         }
      },

      _createGameplaySettingElements: function(name, setting) {
         var self = this;
         // create the elements and functions for getting/setting the setting value
         var newDiv;
         var settingElementID = 'opt__' + name;

         switch(setting.type) {
            case 'boolean':
               newDiv = document.createElement('p');
               newDiv.classList.add('setting');
               var input = document.createElement('input');
               input.type = 'checkbox';
               input.id = settingElementID;
               var label = document.createElement('label');
               label.setAttribute('for', settingElementID);
               self._addTooltip(label, setting.description);
               label.innerHTML = i18n.t(setting.display_name);
               newDiv.appendChild(input);
               newDiv.appendChild(label);

               setting.getValue = function() {
                  return $(input).is(':checked');
               };
               setting.setValue = function(value) {
                  return input.checked = value;
               };
               break;
         }

         return newDiv;
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
