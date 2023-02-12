App.SettingsView = App.View.extend(Ember.ViewTargetActionSupport, {
   templateName: 'settings',
   classNames: ['flex', 'fullScreen', 'exclusive'],
   hideOnCreate: false,
   isMainMenu: false,
   default_max_citizens: 30,
   min_max_citizens: 10,
   max_max_citizens: 80,

   mod_status: {
      NO_ERRORS : 0,
      INVALID_MANIFEST : 1,
      OUT_OF_DATE : 2,
      DEFERRED_LOAD : 3,
      REQUIRED: 4
   },

   graphics_presets: {
      "CUSTOM": -1,
      "MINIMUM": 0,
      "LOW": 1,
      "MEDIUM": 2,
      "HIGH": 3,
      "ULTRA": 4
   },

   init: function() {
      var self = this;
      this._super();

      radiant.call('radiant:get_audio_config')
         .done(function(o) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('audio_options', o);
         });

      radiant.call('radiant:get_config_options')
         .done(function(o) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            if (!o.enable_shadows.allowed) {
               o.enable_shadows.value = false;
            }

            self.set('config_options', o)
         });

      radiant.call('radiant:get_config', 'force_32_bit')
         .done(function(o) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            // if o.force_32_bit is undefined, set it to false
            var enabled = o.force_32_bit == true;
            self.set('force_32_bit', enabled)
         });

      radiant.call('radiant:get_config', 'language')
         .done(function(o) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            var language = o.language;
            if (!language) {
               language = 'en'
            }
            self.set('currentLanguage', language)
         });

      radiant.call_obj('stonehearth.session', 'is_host_player_command')
         .done(function(e) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('isHostPlayer', e.is_host);
         });

      radiant.call('radiant:get_config', 'renderer.graphics_presets')
         .done(function(o) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('graphicsPresets', o['renderer.graphics_presets']);
         });

      $.getJSON('/stonehearth/locales/supported_languages.json', function(data) {
         if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('supported_languages', data.languages)
         });
   },

   actions: {
      useRecommendedGraphicsPreset: function() {
         var preset = this.get('context.recommended_graphics_preset');
         this._updateGraphicsRadioButtons(preset);
         this._changeGraphicsPreset(preset);
      }
   },

   gfxCardString: function() {
      var configOptions = this.get('config_options');
      if (configOptions) {
         var str = i18n.t('stonehearth:ui.shell.settings.gfx_cardinfo', {
               "gpuRenderer": configOptions.gfx_card_renderer,
               "gpuDriver": configOptions.gfx_card_driver
            });

         this.set('gfxCardString', str);
      }
   }.observes('config_options'),

   low_quality : function() {
      return this.get('context.disable_high_quality');
   }.property('context.disable_high_quality'),

   _updateLanguageOptions : function() {
      var languages = this.get('supported_languages');
      var languageArray = [];
      radiant.each(languages, function(key, data) {
         languageArray.push({
            __id: key,
            display_name: data.display_name
         })
      });
      this.set('languages', languageArray);
      this._updateCurrentLanguage();
   }.observes('supported_languages'),

   _updateCurrentLanguage : function() {
      var languages = this.get('supported_languages');
      var currentLanguageKey = this.get('currentLanguage');
      if (currentLanguageKey && languages && (currentLanguageKey in languages)) {
         this.set('currentLanguageData', languages[currentLanguageKey]);
      }
   }.observes('currentLanguage'),

   fromResToVal : function(shadowRes, shadowsEnabled) {
      if (!shadowsEnabled) {
         return 0;
      }
      return shadowRes;
   },

   didInsertElement : function() {
      var self = this;

      // Check to see if we're part of a modal dialog; if so, center us in it!
      if (self.$('#modalOverlay').length > 0) {
         self.$('#settings').position({
               my: 'center center',
               at: 'center center',
               of: '#modalOverlay'
            });
      }

      self.$('.tab').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:page_up' });
         var tabPage = $(this).attr('tabPage');

         self.$('.tabPage').hide();
         self.$('.tab').removeClass('active');
         $(this).addClass('active');

         self.$('#' + tabPage).show();
      });

      self.$('#applyButton').click(function() {
         self.applySettings();
      });

      self.$('#cancelButton').click(function () {
         self.cancel();
      });

      radiant.call('radiant:get_audio_config')
         .done(function(o) {
            //Move to done of other call
            $('#bgmMusicSlider').slider({
               value: o.bgm_volume * 100,
               min: 0,
               max: 100,
               step: 10,
               change: function(event, ui) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
                  self.$('#bgmMusicSliderDescription').html(ui.value + '%');
               },
               slide: function(event, ui) {
                  self.$('#bgmMusicSliderDescription').html(ui.value + '%');
               }
            });
            $('#bgmMusicSliderDescription').html( $("#bgmMusicSlider" ).slider( "value" ) + '%');

            $('#ambientSlider').slider({
               value: o.amb_volume * 100,
               min: 0,
               max: 100,
               step: 10,
               change: function (event, ui) {
                  radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:action_hover' });
                  self.$('#ambientSliderDescription').html(ui.value + '%');
               },
               slide: function (event, ui) {
                  self.$('#ambientSliderDescription').html(ui.value + '%');
               }
            });
            $('#ambientSliderDescription').html($("#ambientSlider").slider("value") + '%');

            $('#effectsSlider').slider({
               value: o.efx_volume * 100,
               min: 0,
               max: 100,
               step: 10,
               change: function(event, ui) {
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
                  self.$('#efxSliderDescription').html(ui.value + '%');
               },
               slide: function(event, ui) {
                  self.$('#efxSliderDescription').html(ui.value + '%');
               }
            });
            $('#efxSliderDescription').html( $("#effectsSlider" ).slider( "value" ) + '%');
         });

      radiant.call('radiant:get_config_options')
         .done(function(o) {
            o.shadow_quality.value = self.fromResToVal(o.shadow_quality.value, o.enable_shadows.value);
            self.oldConfig = {
               "enable_shadows" : o.enable_shadows.value,
               "enable_vsync" : o.enable_vsync.value,
               "shadow_quality": o.shadow_quality.value,
               "max_lights" : o.max_lights.value,
               "max_shadows" : o.max_shadows.value,
               "fullscreen" : o.fullscreen.value,
               "msaa_samples" : o.msaa_samples.value,
               "draw_distance" : o.draw_distance.value,
               "use_high_quality": o.use_high_quality.value,
               "enable_dynamic_icons": o.enable_dynamic_icons.value,
               "enable_ssao" : o.enable_ssao.value,
               "graphics_preset": o.graphics_preset.value
            };
            self._updateGfxTabPage(o);
         });

      radiant.call('radiant:get_config', 'force_32_bit')
         .done(function(o) {
            // if o.force_32_bit is undefined, set it to false
            var enabled = o.force_32_bit == true;
            self.set('context.force_32_bit', enabled);
         });

/*
      radiant.call('radiant:get_config', 'enable_lua_jit')
         .done(function(o) {
            // o.enable_lua_jit can be true, false, or undefined here.  if it's undefined or
            // true, we want to turn 64-bit mode on!
            var enabled = o.enable_lua_jit  != false;
            self.set('context.enable_lua_jit', enabled);
         });
*/

      self._languageChanged = false;
      self._optionPalette = self.$('#languageOptionSelect').stonehearthOptionSelector(
         {
            onSelect: function(itemEle) {
               var langId = itemEle.attr("__id");
               if (langId && langId != self.get('currentLanguage')) {
                  self.set('currentLanguage', itemEle.attr("__id"));
                  self._languageChanged = true;
               }
            },
         });

      $("#selectLanguageButton").click(function() {
         var pos = $(this).offset();
         self._optionPalette.stonehearthOptionSelector('displayOptions', self.get('languages'));
         self._optionPalette.offset(pos);
      });

      $("#collectClientProfile").click(function() {
         radiant.call('radiant:client:log_profile').done(function() {
            $("#collectClientProfile").removeClass('disabled');
         });
         $("#collectClientProfile").addClass('disabled');
      });

      // Check custom preset radio box when these options are changed
      self.$('#opt_disableDeferredRenderer').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
      });

      self.$('#opt_enableSsao').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
      });

      self.$('#opt_enableAntiAliasing').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
      });

      // Update graphics preset and sliders when one of the radio buttons are selected
      self.$('#opt_useCustomGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.CUSTOM);
      });

      self.$('#opt_useMinimumGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.MINIMUM);
      });

      self.$('#opt_useLowGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.LOW);
      });

      self.$('#opt_useMediumGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.MEDIUM);
      });

      self.$('#opt_useHighGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.HIGH);
      });

      self.$('#opt_useUltraGraphics').click(function() {
         self._changeGraphicsPreset(self.graphics_presets.ULTRA);
      });

      // ACE: get gameplay settings for all other mods
      radiant.call('radiant:get_all_mods')
         .done(function(mods) {
            var _mods = {};
            radiant.each(mods, function(_, modData) {
               _mods[modData.name] = modData;
            });
            self._mods = _mods;

            // create collapsible container for [stonehearth] settings and move them into it
            var $gameplayTab = self.$('#gameplayTab');
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

                  self._updateGameplayTabPage();
               });
         });

      self._updateControlsTabPage();

      self.$('label[for=\"opt_disableDeferredRenderer\"]').tooltipster({
         content: $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth:ui.shell.settings.gfx_disable_deferred_renderer_description'))),
      });
      self.$('label[for=\"opt_enableDynamicIcons\"]').tooltipster({
         content: $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth:ui.shell.settings.gfx_enable_dynamic_icons_tooltip'))),
      });
      self.$('label[for=\"opt_infiniteInventory\"]').tooltipster({
         content: $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth:ui.shell.settings.gameplay_tab.infinite_inventory_description'))),
      });
      self.$('label[for=\"opt_enableSpeedThree\"]').tooltipster({
         content: $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth:ui.shell.settings.gameplay_tab.enable_speed_3_description'))),
      });
      self.$('#maxCitizensTitle').tooltipster({
         content: $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth:ui.shell.settings.gameplay_tab.max_citizens_description'))),
      });
      self.$('label').tooltipster();

      if (self.hideOnCreate) {
         self.hide();
      }
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$().off('click');
      this._super();
   },

   dismiss: function () {
      if (this.get('isVisible')) {
         this.cancel();
      }
   },

   hide: function (animate) {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }

      this._super();
   },

   show: function (animate) {
      var self = this;
      this._super();
      App.stonehearth.modalStack.push(self);
   },

   _changeGraphicsPreset: function(preset) {
      if (preset == this.graphics_presets.CUSTOM) {
         this.$('#opt_useCustomGraphics').prop('checked', true);
      }

      this.set('graphicsPreset', preset);
      this._updateGraphicsSliders(preset);
   },

   _updateGraphicsRadioButtons: function(preset) {
      var self = this;
      switch (preset) {
         case self.graphics_presets.CUSTOM:
            self.$('#opt_useCustomGraphics').prop('checked', true);
            break;
         case self.graphics_presets.MINIMUM:
            self.$('#opt_useMinimumGraphics').prop('checked', true);
            break;
         case self.graphics_presets.LOW:
            self.$('#opt_useLowGraphics').prop('checked', true);
            break;
         case self.graphics_presets.MEDIUM:
            self.$('#opt_useMediumGraphics').prop('checked', true);
            break;
         case self.graphics_presets.HIGH:
            self.$('#opt_useHighGraphics').prop('checked', true);
            break;
         case self.graphics_presets.ULTRA:
            self.$('#opt_useUltraGraphics').prop('checked', true);
            break;
      }
   },

   _updateGraphicsSliders: function(preset) {
      var self = this;
      var allPresetSettings = self.get('graphicsPresets');
      var presetSettings = null;
      switch (preset) {
         case self.graphics_presets.CUSTOM:
            // don't update sliders if custom 
            break;
         case self.graphics_presets.MINIMUM:
            presetSettings = allPresetSettings['minimum'];
            break;
         case self.graphics_presets.LOW:
            presetSettings = allPresetSettings['low'];
            break;
         case self.graphics_presets.MEDIUM:
            presetSettings = allPresetSettings['medium'];
            break;
         case self.graphics_presets.HIGH:
            presetSettings = allPresetSettings['high'];
            break;
         case self.graphics_presets.ULTRA:
            presetSettings = allPresetSettings['ultra'];
            break;
      }

      if (!presetSettings) {
         return;
      }

      self.$('#opt_enableVsync').prop('checked', presetSettings.enable_vsync);

      self.$('#shadowResSlider').slider('value', presetSettings.shadow_quality);
      self.$('#shadowResDescription').html(i18n.t('stonehearth:ui.shell.settings.shadow_' + presetSettings.shadow_quality));

      self.$('#maxLightsSlider').slider('value', presetSettings.max_lights);
      self.$('#maxLightsDescription').html(presetSettings.max_lights);

      self.$('#maxShadowsSlider').slider('value', presetSettings.max_shadows);
      self.$('#maxShadowsDescription').html(presetSettings.max_shadows);

      self.$('#drawDistSlider').slider('value', presetSettings.draw_distance);
      self.$('#drawDistDescription').html(presetSettings.draw_distance);

      self.$('#opt_disableDeferredRenderer').prop('checked', !presetSettings.use_high_quality);
      self.set('context.disable_high_quality', !presetSettings.use_high_quality);

      self.$('#opt_enableDynamicIcons').prop('checked', presetSettings.enable_dynamic_icons);

      self.$('#opt_enableSsao').prop('checked', presetSettings.enable_ssao);

      self.$('#opt_enableAntiAliasing').prop('checked', presetSettings.msaa_samples != 0);
   },

   _updateGameplayTabPage: function() {
      var self = this;

      // ACE: we want configs for all mods, not just stonehearth
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

            // apply just the stonehearth settings here (original code)
            var stonehearthOptions = mods.stonehearth;
            if (stonehearthOptions) {
               self.set('showHearthlingPaths', stonehearthOptions.show_hearthling_paths);
               self.set('buildingAutoQueueCrafters', stonehearthOptions.building_auto_queue_crafters === false ? false : true);
               self.set('defaultStorageFilterNone', stonehearthOptions.default_storage_filter_none);
               self.set('defaultMiningZonesSuspended', stonehearthOptions.default_mining_zones_suspended);
               self.set('autoLoot', stonehearthOptions.auto_loot);
               self.set('autoRescue', stonehearthOptions.auto_rescue);
               self.set('enableSpeedThree', stonehearthOptions.enable_speed_three);
               self.set('maxCitizens', stonehearthOptions.max_citizens ? stonehearthOptions.max_citizens : App.constants.population.DEFAULT_MAX_CITIZENS);
               self.set('infiniteInventory', stonehearthOptions.infinite_inventory);
            } else {
               // Set everything to be default
               self.set('buildingAutoQueueCrafters', true);
               self.set('autoLoot', true);
               self.set('autoRescue', false);
               self.set('infiniteInventory', false);
            }
            self.set('oldGameplayOptions', {
               show_hearthling_paths: stonehearthOptions.show_hearthling_paths,
               building_auto_queue_crafters: stonehearthOptions.building_auto_queue_crafters,
               default_storage_filter_none: stonehearthOptions.default_storage_filter_none,
               default_mining_zones_suspended: stonehearthOptions.default_mining_zones_suspended,
               auto_loot: stonehearthOptions.auto_loot,
               auto_rescue: stonehearthOptions.auto_rescue,
               enable_speed_three: stonehearthOptions.enable_speed_three,
               max_citizens: stonehearthOptions.max_citizens,
               infinite_inventory: stonehearthOptions.infinite_inventory,
            });
            self._updateMaxCitizensSlider();
         });
   },

   _getGameplayConfig: function () {
      var result = {
         show_hearthling_paths: $('#opt_showHearthlingPaths').is(':checked'),
         building_auto_queue_crafters: $('#opt_buildingAutoQueueCrafters').is(':checked'),
         default_storage_filter_none: $('#opt_defaultStorageFilterNone').is(':checked'),
         default_mining_zones_suspended: $('#opt_defaultMiningZonesSuspended').is(':checked'),
         auto_loot: $('#opt_autoLoot').is(':checked'),
         auto_rescue: $('#opt_autoRescue').is(':checked'),
         enable_speed_three: $('#opt_enableSpeedThree').is(':checked'),
         max_citizens: $("#maxCitizensSlider").slider("value"),
         infinite_inventory: $("#opt_infiniteInventory").is(':checked'),
      };

      // ACE: include all other non-original gameplay settings
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

   _updateMaxCitizensSlider: function() {
      var self = this;
      var maxCitizensValue = self.get('maxCitizens');
      if (!maxCitizensValue) {
         maxCitizensValue = self.default_max_citizens;
      }
      //Move to done of other call
      $('#maxCitizensSlider').slider({
         value: maxCitizensValue,
         min: self.min_max_citizens,
         max: self.max_max_citizens,
         step: 1,
         change: function(event, ui) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_hover' });
            self.$('#maxCitizensDescription').html(ui.value);
         },
         slide: function(event, ui) {
            self.$('#maxCitizensDescription').html(ui.value);
         }
      });
      $('#maxCitizensDescription').html( $("#maxCitizensSlider" ).slider( "value" ));
   }.observes('maxCitizens'),

   _applyGameplaySettings: function() {
      var self = this;

      // ACE: all the non-original gameplay settings
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

      // Gameplay Settings
      radiant.call('radiant:set_config', 'mods.stonehearth.enable_speed_three', $('#opt_enableSpeedThree').is(':checked'));
      var defaultStorageFilterNone = $('#opt_defaultStorageFilterNone').is(':checked');
      radiant.call('radiant:set_config', 'mods.stonehearth.default_storage_filter_none', defaultStorageFilterNone);
      radiant.call_obj('stonehearth.client_state', 'set_default_storage_filter_none_command', defaultStorageFilterNone);
      radiant.call('radiant:set_config', 'mods.stonehearth.default_mining_zones_suspended', $('#opt_defaultMiningZonesSuspended').is(':checked'));
      radiant.call('radiant:set_config', 'mods.stonehearth.auto_loot', $('#opt_autoLoot').is(':checked'));
      radiant.call('radiant:set_config', 'mods.stonehearth.auto_rescue', $('#opt_autoRescue').is(':checked'));
      radiant.call('radiant:set_config', 'mods.stonehearth.show_hearthling_paths', $('#opt_showHearthlingPaths').is(':checked'));
      radiant.call('radiant:set_config', 'mods.stonehearth.building_auto_queue_crafters', $('#opt_buildingAutoQueueCrafters').is(':checked'));
      radiant.call('radiant:set_config', 'mods.stonehearth.max_citizens', $( "#maxCitizensSlider" ).slider( "value" ));
      radiant.call('radiant:set_config', 'mods.stonehearth.infinite_inventory', $('#opt_infiniteInventory').is(':checked'));
      
      radiant.call('stonehearth:on_client_config_changed');

      // Don't require refresh to enable/disble speedThree.
      if (App.gameView && App.gameView.getView(App.StonehearthGameSpeedWidget)) {
         App.gameView.getView(App.StonehearthGameSpeedWidget).set('enableSpeedThree', $('#opt_enableSpeedThree').is(':checked'));
      }
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
   
         // ACE: increased max draw distance from 1000 to 2000
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

   getGraphicsConfig: function(persistConfig) {
      var newConfig = {
         "enable_shadows" : $( "#shadowResSlider" ).slider( "value" ) > 0,
         "enable_vsync" : $('#opt_enableVsync').is(':checked'),
         "fullscreen" : $('#opt_enableFullscreen').is(':checked'),
         "msaa_samples" : $( "#opt_enableAntiAliasing" ).is(':checked') ? 1 : 0,
         "shadow_quality": this.fromResToVal($("#shadowResSlider").slider("value"), $("#shadowResSlider").slider("value") > 0),
         "max_lights" :  $( "#maxLightsSlider" ).slider( "value" ),
         "max_shadows" :  $( "#maxShadowsSlider" ).slider( "value" ),
         "persistConfig" : persistConfig,
         "draw_distance": $("#drawDistSlider").slider("value"),
         "enable_dynamic_icons" : $('#opt_enableDynamicIcons').is(':checked'),
         "use_high_quality" : !$('#opt_disableDeferredRenderer').is(':checked'),
         "enable_ssao" : $('#opt_enableSsao').is(':checked'),
         "graphics_preset": this.get('graphicsPreset'),
      };
      return newConfig;
   },

   getAudioConfig: function() {
      var newVolumeConfig = {
         "bgm_volume" : this.$( "#bgmMusicSlider" ).slider( "value" ) / 100,
         "amb_volume" : this.$( "#ambientSlider" ).slider( "value" ) / 100,
         "efx_volume" : this.$( "#effectsSlider" ).slider( "value" ) / 100
      };

      return newVolumeConfig;
   },

   applyConfig: function(persistConfig) {
      var self = this;
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:small_click' });
      var newConfig = this.getGraphicsConfig(persistConfig);
      radiant.call('radiant:set_config_options', newConfig);

      var audioConfig = this.getAudioConfig();
      radiant.call('radiant:set_audio_config', audioConfig);

      radiant.call('radiant:set_config', 'force_32_bit', $('#opt_force32bit').is(':checked'));
      //radiant.call('radiant:set_config', 'enable_lua_jit', $('#opt_enableLuaJit').is(':checked'));

      var currentLanguage = this.get('currentLanguage');
      if (currentLanguage) {
         radiant.call('radiant:set_config', 'language', currentLanguage);
      }

      self._applyGameplaySettings();
      var hasModChanges = self._tryConfirmModChanges();

      if (currentLanguage && self._languageChanged && !hasModChanges) {
         radiant.call('radiant:reload_browser');
      }
      
      if (persistConfig) {
         self._saveNewKeyBindings();
      }
   },

   applySettings: function() {
      this.applyConfig(true);
      this.hide();
   },

   _checkShouldHide: function () {
      var self = this;

      // These would perform much better if pushed instead of pulled.
      function hasConfigChanged(oldConfig, newConfig) {
         var result = false;
         radiant.each(oldConfig, function (name, oldValue) {
            var newValue = newConfig[name];
            if (typeof oldValue == 'object') {
               newValue = JSON.stringify(newValue);
               oldValue = JSON.stringify(oldValue);
            }
            if (newValue != oldValue) {
               result = true;
            }
         });
         // Intentionally doesn't check for extra keys in newConfig.
         return result;
      }
      var hasUnsavedChanges = hasConfigChanged(self.oldConfig, self.getGraphicsConfig(false))
                           || hasConfigChanged(self.get('audio_options'), self.getAudioConfig())
                           || self.get('force_32_bit') != $('#opt_force32bit').is(':checked')
                           || self._languageChanged
                           || hasConfigChanged(self.get('oldGameplayOptions'), self._getGameplayConfig())
                           || hasConfigChanged(App.hotkeyManager.getEffectiveBindings(), self.get('keyBindings'))
                           || self._getModChanges().length > 0;

      if (hasUnsavedChanges) {
         self.triggerAction({
            action: 'openInOutlet',
            actionContext: {
               viewName: 'confirm',
               outletName: 'modalmodal',
               controller: {
                  title: i18n.t('stonehearth:ui.shell.settings.unsaved_changes_dialog.title'),
                  message: i18n.t('stonehearth:ui.shell.settings.unsaved_changes_dialog.message'),
                  buttons: [
                     {
                        label: i18n.t('stonehearth:ui.game.common.yes'),
                        click: function () {
                           self.destroy();
                           App.stonehearthClient.showSettings(true);
                        }
                     },
                     {
                        label: i18n.t('stonehearth:ui.game.common.cancel')
                     }
                  ]
               }
            }
         });
         return false;
      } else {
         return true;
      }
   },

   cancel: function () {
      radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:small_click' });
      if (this._checkShouldHide()) {
         this.hide();
      }
   },

   _getModChanges: function() {
      var self = this;
      var modChanges = [];

      var isMainMenu = self.get('isMainMenu');
      if (!isMainMenu) {
         return modChanges;
      }

      var modList = self.get('installedModsList');
      var modsChanged = false;
      radiant.each(modList, function(i, modInfo) {
         if (!modInfo.unavailable) {
            var modEnabled = $('#' + modInfo.id).is(':checked');
            if (modEnabled != modInfo.userEnabled) {
               modsChanged = true;
               modChanges.push({
                  name: modInfo.name,
                  enabled: modEnabled});
            }
         }
      });
      return modChanges;
   },

   _tryConfirmModChanges: function() {
      var self = this;
      var modChanges = self._getModChanges();
      if (modChanges.length <= 0) {
         return false;
      }

      App.shellView.addView(App.StonehearthConfirmView,
         {
            title : i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.title'),
            message : i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.message'),
            buttons : [
               {
                  label: i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.accept'),
                  click: function () {
                     radiant.each(modChanges, function(i, change) {
                           radiant.call('radiant:set_config', 'mods.' + change.name + '.enabled', change.enabled);
                     });
                     radiant.call('radiant:client:return_to_main_menu');
                  }
               },
               {
                  label: i18n.t('stonehearth:ui.shell.settings.mods_tab.mods_changed_dialog.cancel'),
                  click: function () {
                     if (self._languageChanged) {
                        // if the user cancelled changing mods, we should still reload the browser because
                        // the language changed
                        radiant.call('radiant:reload_browser');
                     }
                  }
               }
            ]
         });
      return true;
   },

   _categorizeKeyBindings: function () {
      var self = this;
      var bindings = self.get('keyBindings');
      
      var combos = [];
      _.each(bindings, function (hotkeyDefinition) {
         combos.push(hotkeyDefinition.combo1);
         combos.push(hotkeyDefinition.combo2);
      });
      App.hotkeyManager.getPrettyKeyComboNames(combos).done(function (names) {
         var comboNames = {};
         _.each(Object.keys(bindings), function (bindingId, i) {
            comboNames[bindingId] = {combo1: names[i * 2] || '', combo2: names[i * 2 + 1] || ''};
         });

         var compareOrdinal = function (a, b) {
            return (a.ordinal || 0) - (b.ordinal || 0);
         };
         var categories = App.hotkeyManager.getHotkeyCategories();
         categories[''] = {
            displayName: 'i18n(stonehearth:ui.shell.settings.controls_tab.key_category_names.other)',
            ordinal: Infinity
         };
         self.set('categorizedKeyBindings', _.map(categories, function (categoryDefinition, categoryId) {
            return {
               name: i18n.t(categoryDefinition.displayName),
               ordinal: categoryDefinition.ordinal,
               keys: _.map(bindings, function (hotkeyDefinition, bindingId) {
                  return {
                     id: bindingId,
                     categoryId: hotkeyDefinition.category,
                     ordinal: hotkeyDefinition.ordinal,
                     name: i18n.t(hotkeyDefinition.displayName),
                     combo1: comboNames[bindingId].combo1,
                     combo2: comboNames[bindingId].combo2,
                  };
               }).filter(function (binding) {
                  return (binding.categoryId || '') == categoryId;
               }).sort(compareOrdinal)
            }
         }).filter(function (category) {
            return !_.isEmpty(category.keys);
         }).sort(compareOrdinal));
      });
   }.observes('keyBindings'),

   _updateControlsTabPage: function () {
      var self = this;

      self.set('categorizedKeyBindings', []);
      self.set('keyBindings', App.hotkeyManager.getEffectiveBindings());

      self.$().on('click', '#resetToDefaults', function () {
         self.set('keyBindings', App.hotkeyManager.getHotkeyDefinitions());
      });

      self.$().on('click', '.bindingEntry button', function () {
         var button = $(this);
         button.addClass('active');

         function swallowKeyUps(e) {
            e.preventDefault();
            e.stopPropagation();
         }
         function catchKeyDown(e) {
            var MODIFIERS = ['shiftleft', 'controlleft', 'altleft', 'metaleft',
                             'shiftright', 'controlright', 'altright', 'metaright'];
            var keyCode = e.code.toLowerCase();
            if (keyCode && MODIFIERS.indexOf(keyCode) == -1) {
               stopListeningForNewKeyBind();

               if (keyCode != 'escape') {
                  var keyCombo = '';
                  if (keyCode != 'delete') {
                     if (e.altKey) {
                        keyCombo += "alt+";
                     }
                     if (e.ctrlKey) {
                        keyCombo += "ctrl+";
                     }
                     if (e.metaKey) {
                        keyCombo += "meta+";
                     }
                     if (e.shiftKey) {
                        keyCombo += "shift+";
                     }
                     keyCombo += keyCode;
                  }

                  var bindingId = button.closest('.bindingEntry').attr('keyBindingId');
                  self._tryChangeKeyBind(button, bindingId, keyCombo);
               }
            }

            e.preventDefault();
            e.stopPropagation();
         }
         function stopListeningForNewKeyBind() {
            button.removeClass('active');
            document.removeEventListener('keydown', catchKeyDown, true);
            document.removeEventListener('mousedown', stopListeningForNewKeyBind, true);
            setTimeout(function () {
               // We are doing this in response to a keydown, so wait a moment to ignore its keyup.
               document.removeEventListener('keyup', swallowKeyUps, true);
               radiant.call('radiant:set_hotkeys_enabled', true);
            }, 300);
         }
         // Have to do this natively; otherwise jQuery listeners on other things capture this.
         document.addEventListener('keydown', catchKeyDown, true);
         document.addEventListener('keyup', swallowKeyUps, true);
         document.addEventListener('mousedown', stopListeningForNewKeyBind, true);
         radiant.call('radiant:set_hotkeys_enabled', false);
      });
   },

   _tryChangeKeyBind: function (button, bindingId, keyCombo) {
      var self = this;

      // Check for conflicts.
      var conflicts = [];
      if (keyCombo && !App.hotkeyManager.isMask(keyCombo)) {
         radiant.each(self.get('keyBindings'), function (bindingId2, combos) {
            if (bindingId != bindingId2 && (combos.combo1 == keyCombo || combos.combo2 == keyCombo)) {
               conflicts.push(bindingId2);
            }
         });
      }

      // Just assign and return if we have no conflicts.
      if (_.isEmpty(conflicts)) {
         self._changeKeyBind(button, bindingId, keyCombo);
         return;
      }

      // We need to ask the user how to deal with the conflict.
      button.addClass('active');
      var conflictsString = conflicts.map(function (bindingId2) {
         return i18n.t(self.get('keyBindings')[bindingId2].displayName);
      }).join(', ');
      App.hotkeyManager.getPrettyKeyComboNames([keyCombo]).done(function (keyComboNames) {
         self.triggerAction({
            action: 'openInOutlet',
            actionContext: {
               viewName: 'confirm',
               outletName: 'modalmodal',
               controller: {
                  title: i18n.t('stonehearth:ui.shell.settings.controls_tab.conflict_dialog.title'),
                  message: i18n.t('stonehearth:ui.shell.settings.controls_tab.conflict_dialog.message',
                                  { combo: keyComboNames[0], conflicts: conflictsString }),
                  buttons: [
                     {
                        label: i18n.t('stonehearth:ui.shell.settings.controls_tab.conflict_dialog.choice_replace'),
                        click: function () {
                           // Unbind all but this.
                           conflicts.forEach(function (bindingId2) {
                              var combos = self.get('keyBindings')[bindingId2];
                              if (combos.combo1 == keyCombo) {
                                 delete combos.combo1;
                              } else if (combos.combo2 == keyCombo) {
                                 delete combos.combo2;
                              }
                           });
                           self._changeKeyBind(button, bindingId, keyCombo);
                        }
                     },
                     {
                        label: i18n.t('stonehearth:ui.shell.settings.controls_tab.conflict_dialog.choice_keep'),
                        click: function () {
                           // Keep conflicts. Can be valid if the keys are used in different contexts.
                           self._changeKeyBind(button, bindingId, keyCombo);
                        }
                     },
                     {
                        label: i18n.t('stonehearth:ui.shell.settings.controls_tab.conflict_dialog.choice_cancel')
                     }
                  ],
                  onDestroy: function () {
                     button.removeClass('active');
                  }
               }
            }
         });
      });
   },

   _changeKeyBind: function (button, bindingId, keyCombo) {
      var whichCombo = button.is('.combo1') ? 'combo1' : 'combo2';
      if (keyCombo) {
         this.get('keyBindings')[bindingId][whichCombo] = keyCombo;
      } else {
         delete this.get('keyBindings')[bindingId][whichCombo];
      }
      this.notifyPropertyChange('keyBindings');
   },

   _saveNewKeyBindings: function () {
      App.hotkeyManager.setUserBindingsFromEffectiveBindings(this.get('keyBindings'))
         .done(function () {
            // Update currently live bindings.
            App.hotkeyManager.unbindActionsWithin(document);
            App.hotkeyManager.bindActionsWithin(document);
         })
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
               input.prop('checked', !!value);
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
               slider.slider({value: Math.max(ns.min, Math.min(ns.max, value))});
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
               var listVal = vals[value] || vals[setting.default];
               if (listVal != null) {
                  App.guiHelper.setListSelectorValue(selector, listVal);
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
