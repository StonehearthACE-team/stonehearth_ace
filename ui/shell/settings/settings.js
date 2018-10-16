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
            if(mod == 'stonehearth') {
               // if it's the stonehearth mod, we need to get the values from _getGameplayConfig
               var shSettings = self._getGameplayConfig();
               radiant.each(modSettings, function(name, setting){
                  if(shSettings[name] != undefined) {
                     setting.value = shSettings[name];
                  }
               });
            }
            else {
               radiant.each(modSettings, function(name, setting){
                  if(setting.getValue) {
                     var value = setting.getValue();
                     setting.value = value;
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
               newDiv = document.createElement('div');
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

      _addTooltip: function(itemEl, title) {
         var tooltip = App.tooltipHelper.createTooltip("", i18n.t(title), "");
         $(itemEl).tooltipster({ content: $(tooltip) });
      }
   });
});
