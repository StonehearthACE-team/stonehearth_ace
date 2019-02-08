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
               var newParent = self._createGameplayDivForMod('stonehearth');
               newParent.section.append($gameplayTab.children());
               var accordion = $('<div>')
                  .attr('id', 'modSettingsAccordion')
                  .append(newParent.header)
                  .append(newParent.section);

               $gameplayTab.append(accordion);

               // load up settings from client state (only care about mod settings, not [stonehearth] overrides)
               radiant.call('stonehearth_ace:get_all_client_gameplay_settings_command')
                  .done(function(response){
                     var settings = response.settings;
                     self._settings = settings;

                     // create collapsible containers for other mods' settings and create their settings within them
                     radiant.each(settings, function(mod, modSettings) {
                        if(mod != 'stonehearth') {
                           newParent = self._createGameplayDivForMod(mod, modSettings);
                           accordion.append(newParent.header);
                           accordion.append(newParent.section);
                        }
                     });

                     accordion.accordion({
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
                        var fire_event = setting.on_change.fire_event;
                        if(fire_event) {
                           var e = {
                              mod : mod,
                              setting : setting.name,
                              value : setting.value,
                              args : setting.on_change.args
                           };
                           $(top).trigger(fire_event, e);
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
            var newHeader = $('<h3>')
               .addClass('modHeader')
               .html(title);
            var newSection = $('<div>')
               .addClass('modSettings');

            if(settings) {
               var isHost = self.get('isHostPlayer');
               // if there are actually settings, create the elements for them, sorted by ordinal
               var sortedSettings = radiant.map_to_array(settings, function(name, setting) {
                  setting.name = name;
                  setting.ordinal = setting.ordinal || 0;
               });
               sortedSettings.sort(function(a, b) { return a.ordinal - b.ordinal });

               radiant.each(sortedSettings, function(i, setting) {
                  if (isHost || !setting.host_only) {
                     var element = self._createGameplaySettingElements(mod, setting);
                     if(element) {
                        newSection.append(element);
                     }
                  }
               });
            }

            return {header: newHeader, section: newSection};
         }
      },

      _createGameplaySettingElements: function(mod, setting) {
         var self = this;
         // create the elements and functions for getting/setting the setting value
         var newDiv;
         var settingElementID = 'opt__' + mod + '__' + setting.name;

         switch(setting.type) {
            case 'boolean':
               newDiv = $('<div>')
                  .addClass('setting');

               var input = $('<input>')
                  .attr('type', 'checkbox')
                  .attr('id', settingElementID);
               
               var label = $('<label>')
                  .attr('for', settingElementID)
                  .html(i18n.t(setting.display_name));

               App.guiHelper.addTooltip(label, setting.description);

               newDiv.append(input);
               newDiv.append(label);

               setting.getValue = function() {
                  return input.is(':checked');
               };
               setting.setValue = function(value) {
                  input.prop('checked', value);
               };

               break;

            case 'number':
               var ns = self._getNumberSettings(setting.number_settings);
               newDiv = $('<div>')
                  .addClass('setting');

               var title = $('<label>')
                  .html(i18n.t(setting.display_name));

               App.guiHelper.addTooltip(title, setting.description);

               var slider = $('<div>');
               var description = $('<div>')
                  .addClass('sliderDescription');

               newDiv.append(title);
               newDiv.append(slider);
               newDiv.append(description);

               slider.slider({
                  value: setting.value,
                  min: ns.min,
                  max: ns.max,
                  step: ns.step,
                  change: function(event, ui) {
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
                     description.html(ui.value);
                  },
                  slide: function(event, ui) {
                     description.html(ui.value);
                  }
               });
               
               setting.getValue = function() {
                  return slider.slider('value');
               };
               setting.setValue = function(value) {
                  slider.slider({value: value});
                  description.innerHTML = value;
               }
               
               break;

            case 'list':
               var vals = setting.values;
               // map values to an array and sort by ordinal if available, otherwise by key (value)
               var valsArr = radiant.map_to_array(vals, function(k, v) {
                  v.key = k;
               });
               valsArr.sort(function(a, b) {
                  var result = self._compareNullablesAsc(a.ordinal, b.ordinal);
                  if (result != null) {
                     return result;
                  }
                  else {
                     return self._compareAsc(a.key, b.key);
                  }
               });

               newDiv = $('<div>')
                  .addClass('setting list-setting');

               var selector = App.guiHelper.createCustomSelector(settingElementID, valsArr);

               var label = $('<span>')
                  .addClass('list-label');

               App.guiHelper.addTooltip(label, setting.description);
               label.html(i18n.t(setting.display_name));

               newDiv.append(label);
               newDiv.append(selector);

               setting.getValue = function() {
                  return App.guiHelper.getListSelectorValue(selector);
               };

               setting.setValue = function (value) {
                  // make sure this value is available (could be a modded value with that mod turned off)
                  if (vals[value] != null) {
                     App.guiHelper.setListSelectorValue(selector, vals[value]);
                  }
               };

               break;
         }

         setting.setValue(setting.value);

         return newDiv;
      },

      _getNumberSettings: function (ns) {
         ns = ns || {};
         ns.min = ns.min || 0;
         ns.max = ns.max || Math.max(0, 1 + ns.min);
         ns.step = ns.step || 1;

         return ns;
      },

      _compareNullablesAsc: function(a, b) {
         if (a == null && b == null) {
            return null;
         }
         else if (a == null) {
            return 1;
         }
         else if (b == null) {
            return -1;
         }
         else {
            return this._compareAsc(a, b);
         }
      },

      _compareAsc: function(a, b) {
         return a < b ? -1 : (a > b ? 1 : 0);
      }
   });
});
