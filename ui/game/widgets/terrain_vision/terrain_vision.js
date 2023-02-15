App.StonehearthTerrainVisionWidget = App.View.extend({
   templateName: 'stonehearthTerrainVision',
   uriProperty: 'model',

   init: function() {
      var self = this;

      self._super();

      // ACE: removed appeal heatmap button and added generic heatmap service handling
      radiant.call('stonehearth_ace:get_client_service', 'heatmap').done(function (r) {
         self._heatmapServiceAddress = r.result;
         radiant.call_obj('stonehearth_ace.heatmap', 'get_heatmaps_command').done(function (response) {
            var heatmaps = response.heatmaps;
            radiant.each(heatmaps, function(key, heatmap) {
               heatmap.key = key;
               heatmap.description = i18n.t(heatmap.description);
            });
            self._heatmaps = heatmaps;
            
            var heatmapArray = radiant.map_to_array(heatmaps)
            radiant.sortByOrdinal(heatmapArray);
            self.set('heatMaps', heatmapArray);

            Ember.run.scheduleOnce('afterRender', function() {
               var heatmaps = self.$('.heatmap');
               if (heatmaps) {
                  heatmaps.each(function(i) {
                     App.hotkeyManager.makeTooltipWithHotkeys($(this),
                           $(this).attr('title'),
                           $(this).attr('description'));
                  });
               }
            });
         });
      });
   },

   _currentTip: null,
   didInsertElement: function() {
      var self = this;
      // Position children and bind hotkeys to clicks
      this._super();

      // Setup tooltips for the vision buttons
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#visionButton'),
                                               'stonehearth:ui.game.visions.building_vision',
                                               'stonehearth:ui.game.visions.building_vision_description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#sliceButton'),
                                               'stonehearth:ui.game.visions.terrain_slice_vision',
                                               'stonehearth:ui.game.visions.terrain_slice_vision_description');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#clipUp'),
                                               'stonehearth:ui.game.visions.terrain_slice_vision_up');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#clipUpSingle'),
                                               'stonehearth:ui.game.visions.terrain_slice_vision_up_single');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#clipDownSingle'),
                                               'stonehearth:ui.game.visions.terrain_slice_vision_down_single');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#clipDown'),
                                               'stonehearth:ui.game.visions.terrain_slice_vision_down');
      App.hotkeyManager.makeTooltipWithHotkeys(this.$('#xrayButton'),
                                               'stonehearth:ui.game.visions.terrain_xray_vision',
                                               'stonehearth:ui.game.visions.terrain_xray_vision_description');

      // ACE: removed appeal heatmap button and added generic heatmap service handling
      App.hotkeyManager.makeTooltipWithHotkeys(self.$('#heatmapButton'),
            'stonehearth_ace:ui.game.visions.heatmap.title',
            'stonehearth_ace:ui.game.visions.heatmap.description');

      this.$('#visionButton').click(this.modeChangeClickHandler());
      this.$(top).on('stonehearthVisionModeChange', this.modeChangeHandler());

      this.$('#xrayButton').click(function() {
         self.setClip(false);

         var currentMode = self.get('xray_mode')
         var newMode;

         if (!currentMode) {
            newMode = self._lastMode || 'full';
            self._currentTip = App.stonehearthClient.showTip('stonehearth:ui.game.visions.terrain_xray_vision',
                                          'stonehearth:ui.game.visions.terrain_xray_vision_description',
                                          { i18n : true, timeout : 2000 }
                                       );
         } else {
            newMode = null;
            App.stonehearthClient.hideTip(self._currentTip);
         }

         self.setXRayMode(newMode);
      });

      this.$('.xrayButton').click(function() {
         self.setClip(false);

         var currentMode = self.get('xray_mode')
         var newMode = $(this).attr('mode');

         if (newMode == currentMode) {
            newMode = null;
         }

         self._lastMode = newMode
         self.setXRayMode(newMode);
      });

      this.$('#sliceButton').click(function() {
         self.setXRayMode(null);

         var button = $(this);
         var currentlyClipping = button.hasClass('clip');

         // toggle slice modes
         if (currentlyClipping) {
            self.setClip(false);
            self.set('clip_enabled', false);
         } else {
            self.setClip(true);
            self.set('clip_enabled', true);
         }
      });

      this.$('#clipUp').click(function () {
         self.setXRayMode(null);
         self.moveUp();
      });

      this.$('#clipUpSingle').click(function () {
         self.setXRayMode(null);
         self.moveUpSingle();
      });

      this.$('#clipDownSingle').click(function () {
         self.setXRayMode(null);
         self.moveDownSingle();
      });

      this.$('#clipDown').click(function () {
         self.setXRayMode(null);
         self.moveDown();
      });

      // Key input tracing
      //$(document).keydown(function(e) {
      //   logEvent(e.originalEvent);
      //});

      self._updatePaletteLocation('slice');
      self._updatePaletteLocation('xray');

      Ember.run.scheduleOnce('afterRender', this, function() {
         radiant.call_obj('stonehearth.subterranean_view', 'get_subterranean_state_command')
            .done(function(response) {
               self.set('clip_enabled', response.clip_enabled);
               if (response.clip_enabled) {
                  self.set('clip_height', response.clip_height);
               } else if (response.xray_mode) {
                  self.set('xray_mode', response.xray_mode);
               }
            });
      });

      // when the user clicks the heatmap menu button, show/hide the current heatmap and the menu
      self.$('#heatmapButton').on('click', function() {
         var shown = self.get('heatmapShown');
         shown = !shown;
         self.set('heatmapShown', shown);
         if (!shown) {
            self.setHeatmapActive();
         }
      });
      // when the user clicks a heatmap button, show that heatmap and hide the menu
      var heatmapList = self.$('#heatmapList');
      heatmapList.on('click', '.heatmap', function() {
         event.stopPropagation();
         var key = $(this).attr('data-key');
         self.setHeatmapActive(key, true);
         self.set('heatmapShown', false);
         //heatmapList.hide();
         //heatmapList.attr('style', '');
      });

      // this is a call to a global function stored in task_manager.js
      //_updateProcessingMeterShown();
   },

   modeChangeClickHandler: function() {
      var self = this;
      return function() {
         var currentMode = App.getVisionMode();

         if (currentMode == 'normal') {
            currentMode = 'xray';
         } else if (currentMode == 'xray') {
            currentMode = 'rpg';
         } else {
            currentMode = 'normal';
         }
         App.setVisionMode(currentMode);
      };
   },

   modeChangeHandler: function() {
      var self = this;
      return function(e, newMode) {
         self.$('#visionButton').attr('class', newMode);
      };
   },

   _updatePaletteLocation: function(paletteName) {
      var buttonLocLeft = this.$('#' + paletteName + 'Button').offset().left - 4;
      var buttonWidth = this.$('#' + paletteName + 'Button').width();
      var palette = this.$('#' + paletteName + 'Palette');
      var paletteWidth = palette.width();
      var difference = (paletteWidth - buttonWidth) / 2;
      palette.offset({left: buttonLocLeft - difference});
   },

   setHeatmapActive: function (heatmapKey, isActive) {
      var self = this;
      // if heatmapKey is null, we're making it inactive
      isActive = isActive && (heatmapKey != null);
      self.set('heatmap_active', isActive);
      if (self._heatmapValueTrace) {
         self._heatmapValueTrace.destroy();
      }
      var heatmapData = self._heatmaps && self._heatmaps[heatmapKey];
      if (isActive && heatmapData) {
         radiant.call_obj('stonehearth_ace.heatmap', 'show_heatmap_command', heatmapKey)
            .done(function(response) {
               if(heatmapKey != null && response.hidden) {
                  self.setHeatmapActive(heatmapKey, false);
               }
            });
         self._currentTip = App.stonehearthClient.showTip(heatmapData.name, heatmapData.description, { i18n: true });
         self._heatmapValueTrace = new RadiantTrace();
         self._heatmapValueTrace.traceUri(self._heatmapServiceAddress, {}).progress(function (response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            var heat_value = response.current_probe_value;
            self.set('currentHeatValue', response.current_probe_value);
            if (heatmapData.constants_key) {
               var thresholds = radiant.deep_copy_pod(self.getDescendantProp(App.constants, heatmapData.constants_key + '.LEVELS'));
               for (var i = 0; i < thresholds.length; ++i) {
                  var threshold = thresholds[i];
                  if (heat_value < threshold.max) {
                        var icon_path = threshold.icon
                        if (icon_path[0] != '/') {
                           icon_path = '/stonehearth/data/horde/' + icon_path;
                        }
                        self.set('currentHeatValueIcon', icon_path);
                        self.set('currentHeatValueLabel', i18n.t(threshold.ui_label).replace(/\s+/g, '<br/>'));
                        break;
                  }
               };
            }
            else {
               self.set('currentHeatValueIcon', heatmapData.icon);
               self.set('currentHeatValueLabel', i18n.t(heatmapData.description).replace(/\s+/g, '<br/>'));
            }
         });
         $(document).bind('mousemove.heatmapCursorReadout', function (e) {
            var readout = $('#heatmapCursorReadout');
            readout.css({ left: e.pageX - readout.width() / 2 + 16, top: e.pageY });
            var handle = $('#heatmapCursorReadout .handle');
            handle.css({ left: readout.width() / 2 - handle.width() / 2 });
         });
      } else {
         App.stonehearthClient.hideTip(self._currentTip);
         self.set('currentHeatValue', null);
         self.set('currentHeatValueIcon', null);
         self.set('currentHeatValueLabel', null);
         radiant.call_obj('stonehearth_ace.heatmap', 'hide_heatmap_command');
         $(document).unbind('mousemove.heatmapCursorReadout');
      }
   },

   setXRayMode: function(mode) {
      var self = this;
      self.set('xray_mode', mode)
      radiant.call_obj('stonehearth.subterranean_view', 'toggle_xray_mode_command', mode);
   },

   setClip: function(enabled) {
      var self = this;
      return radiant.call_obj('stonehearth.subterranean_view', 'set_clip_enabled_command', enabled)
         .done(function(response) {
            self.set('clip_enabled', response.enabled);
            if (response.enabled) {
               self.set('clip_height', response.clip_height);
            }
         });
   },

   moveUp: function() {
      var self = this;
      radiant.call_obj('stonehearth.subterranean_view', 'set_clip_enabled_command', true)
         .done(function(response) {
            if (response) {
               radiant.call_obj('stonehearth.subterranean_view', 'move_clip_height_up_command')
                  .done(function(e) {
                     self.set('clip_height', e.new_height)
                  });;
            }
         })
   },

   moveUpSingle: function () {
      var self = this;
      radiant.call_obj('stonehearth.subterranean_view', 'set_clip_enabled_command', true)
         .done(function (response) {
            if (response) {
               radiant.call_obj('stonehearth.subterranean_view', 'move_clip_height_up_single_command')
                  .done(function (e) {
                     self.set('clip_height', e.new_height)
                  });;
            }
         })
   },

   moveDown: function() {
      var self = this;
      radiant.call_obj('stonehearth.subterranean_view', 'set_clip_enabled_command', true)
         .done(function(response) {
            if (response) {
               radiant.call_obj('stonehearth.subterranean_view', 'move_clip_height_down_command')
                  .done(function(e) {
                     self.set('clip_height', e.new_height)
                  });
            }
         })
   },

   moveDownSingle: function () {
      var self = this;
      radiant.call_obj('stonehearth.subterranean_view', 'set_clip_enabled_command', true)
         .done(function (response) {
            if (response) {
               radiant.call_obj('stonehearth.subterranean_view', 'move_clip_height_down_single_command')
                  .done(function (e) {
                     self.set('clip_height', e.new_height)
                  });
            }
         })
   },

   // source: https://stackoverflow.com/questions/8051975/access-object-child-properties-using-a-dot-notation-string
   // is there a radiant version of this somewhere?
   getDescendantProp: function (obj, desc) {
      var arr = desc.split('.');
      while (arr.length && (obj = obj[arr.shift()]));
      return obj;
   },
});
