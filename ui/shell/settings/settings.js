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
                           if (newParent) {
                              accordion.append(newParent.header);
                              accordion.append(newParent.section);
                           }
                        }
                     });

                     accordion.accordion({
                        heightStyle: "content"
                     });

                     self._updateModifiedGameplayTabPage();
                  });
            });
      },

      _updateGfxTabPage: function(o) {
         var self = this;
   
         self.set('context.shadows_forbidden', !o.enable_shadows.allowed);
         if (!o.enable_shadows.allowed) {
            o.enable_shadows.value = false;
         }
         self.set('context.enable_shadows', o.enable_shadows.value);
         self.set('context.shadow_quality', o.shadow_quality.value)
         self.set('context.max_lights', o.max_lights.value)
         self.set('context.max_shadows', o.max_shadows.value)
         self.set('context.vsync_enabled', o.enable_vsync.value);
         self.set('context.fullscreen_enabled', o.fullscreen.value);
   
         self.set('context.enable_antialiasing', o.msaa_samples.value != 0);
         self.set('context.draw_distance', o.draw_distance.value);
   
         self.set('context.enable_ssao', o.enable_ssao.value);
         self.set('context.enable_dynamic_icons', o.enable_dynamic_icons.value);
   
         self.set('context.high_quality_forbidden', !o.use_high_quality.allowed);
         if (!o.use_high_quality.allowed) {
            o.use_high_quality.value = false;
         }
         self.set('context.disable_high_quality', !o.use_high_quality.value);
   
         self.set('context.recommended_graphics_preset', o.recommended_graphics_preset.value);
         self.set('graphicsPreset', o.graphics_preset.value);
   
         self._updateGraphicsRadioButtons(o.graphics_preset.value);
   
         $('#shadowResSlider').slider({
            value: self.get('context.shadow_quality'),
            min: 0,
            max: 5,
            step: 1,
            disabled: self.get('context.shadows_forbidden'),
            slide: function( event, ui ) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
               $('#shadowResDescription').html(i18n.t('stonehearth:ui.shell.settings.shadow_' + ui.value));
               // Note: this can't be in a slider.change callback because we change the sliders when
               // changing a graphics preset, which would cause the custom radio button to always get checked
               if (ui.value != self.$('shadowResSlider').slider('value')) {
                  self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
               }
            }
         });
         $('#shadowResDescription').html(i18n.t('stonehearth:ui.shell.settings.shadow_' + self.get('context.shadow_quality')));
   
         $('#maxLightsSlider').slider({
            value: self.get('context.max_lights'),
            min: 1,
            max: 250,
            step: 1,
            slide: function( event, ui ) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
               $('#maxLightsDescription').html(ui.value);
               if (ui.value != self.$('maxLightsSlider').slider('value')) {
                  self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
               }
            }
         });
         $('#maxLightsDescription').html(self.get('context.max_lights'));
   
         $('#maxShadowsSlider').slider({
            value: self.get('context.max_shadows'),
            min: 0,
            max: 16,
            step: 1,
            slide: function( event, ui ) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
               $('#maxShadowsDescription').html(ui.value);
               if (ui.value != self.$('maxShadowsSlider').slider('value')) {
                  self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
               }
            }
         });
         $('#maxShadowsDescription').html(self.get('context.max_shadows'));
   
         $('#drawDistSlider').slider({
            value: self.get('context.draw_distance'),
            min: 500,
            max: 2000,
            step: 20,
            slide: function( event, ui ) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
               $('#drawDistDescription').html(ui.value);
               if (ui.value != self.$('drawDistSlider').slider('value')) {
                  self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
               }
            }
         });
         $('#drawDistDescription').html(self.get('context.draw_distance'));
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
         self._super(); // call this last, because it triggers a client-side event ('stonehearth_ace:client_config_changed')
      },

      _createGameplayDivForMod: function(mod, settings) {
         var self = this;
         var modData = self._mods && self._mods[mod];
         var hasList = false;
         var heightSinceList = 0;
         var totalHeight = 0;

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

                        // TODO: these heights are hard-coded! bad! but a hack to get it to render enough space for drop downs
                        switch (setting.type) {
                           case 'list':
                              hasList = true;
                              totalHeight += 74;
                              heightSinceList = 0;
                              break;
                           case 'boolean':
                              totalHeight += 48;
                              heightSinceList += 48;
                              break;
                           case 'number':
                              totalHeight += 88;
                              heightSinceList += 88;
                              break;
                        }
                     }
                  }
               });
            }

            if (hasList && heightSinceList < 200) {
               // if there's a list, make sure we add some extra space at the bottom
               newSection.height(totalHeight + 200 - heightSinceList);
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

               var selector = App.guiHelper.createCustomSelector(settingElementID, valsArr).container;

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
