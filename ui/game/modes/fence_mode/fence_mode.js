App.AceBuildFenceModeView = App.View.extend({
   templateName: 'fenceMode',
   closeOnEsc: false,
   modal: false,

   _shownFirstTime: false,

   dismiss: function() {
      this.hide();
   },

   show: function() {
      var self = this;
      var isVisible = self.visible();
      self._super();
      
      // only perform initialization stuff if the view wasn't already visible
      if (!isVisible) {
         if (!self._shownFirstTime) {
            self._shownFirstTime = true;
            self._loadSegments();
            self._loadPresets();
            self._loadConfigSegments();
         }
         else {
            self.buildFence();
         }
      }
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self._fenceData = stonehearth_ace.getFenceModeData();

      var segmentsDiv = self.$('#fenceSegmentsDiv');
      segmentsDiv.on('mousemove', function(e) {
         var segments = self.get('segments') || [];
         if (self.$('#presetSelection').is(':visible') || self.$('#segmentSelection').is(':visible') ||
               segments.length > 20) {
            self.set('canAddSegment', false);
            return;
         }

         // find the appropriate insert index based on location
         var x = e.pageX - segmentsDiv.offset().left;
         var y = e.pageY - segmentsDiv.offset().top;
         var index = Math.floor((x - 5) / 75 + 0.5);
         self._insertIndex = index;
         var btn = self.$('#addSegmentBtn');
         var left = index * 75 - btn.width() / 2 + 5;
         btn.css('left', left);
         self.set('canAddSegment', y < 60 && Math.abs(x - left) < 50);
      });
      self.$().on('contextmenu', '.toggleSegmentBtn', function() {
         var index = $(this).data('index');
         var segments = self.get('segments');
         var newSegments = [];
         for (var i = 0; i < segments.length; i++) {
            if (i != index) {
               var newSegment = self._getProperSegment(segments[i].uri, segments[i].enabled);
               newSegments.push(newSegment);
            }
         }
         for (var i = newSegments.length; i < 2; i++) {
            var newSegment = self._getProperSegment(newSegments[i - 1].uri, false);
            newSegments.push(newSegment);
         }
         self._setCurrentSegments(newSegments);
         self._updateSegmentsConfig();
         self.$('#segmentSelection').hide();

         return false;
      });

      App.jobController.addChangeCallback('fence_mode', function() {
         self._updateAvailability();
      }, true);

      App.tooltipHelper.attachTooltipster(self.$('#showLoadPreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_load.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_load.description')))
      );
      App.tooltipHelper.attachTooltipster(self.$('#showSavePreset'),
         $(App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_save.title'),
            i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.show_save.description')))
      );
   },

   willDestroyElement: function() {
      App.jobController.removeChangeCallback('fence_mode');
      this.$().find('.tooltipstered').tooltipster('destroy');
   },

   _loadSegments: function() {
      var self = this;
      var segments = [];
      self._segments = {};

      var allFences = App.catalog.getFilteredCatalogData('fence', function(uri, catalogData) {
         return catalogData.fence_length != null && uri[0] != '/';
      });
      radiant.each(allFences, function(uri, catalogData) {
         var segment = {
            uri: uri,
            length: catalogData.fence_length,
            icon: catalogData.icon,
            display_name: catalogData.display_name,
            description: catalogData.description
         };
         self._segments[uri] = segment;
         segments.push(segment);
      });

      // maybe we'll divide them into categories at some point; for now, just sort them by uri and lump them all together
      segments.sort((a, b) => a.uri.localeCompare(b.uri));
      self.set('allSegments', segments);
      Ember.run.scheduleOnce('afterRender', self, '_updateAllSegmentTooltips');
   },

   _loadPresets: function() {
      var self = this;
      // first add the default presets; then add the custom presets
      var presets = [];
      self._defaultPresets = {};
      self._customPresets = {};

      radiant.each(self._fenceData.default_presets, function(name, segments) {
         var preset = self._createPresetObj(name, segments);
         preset.default = true;
         presets.push(preset);
         self._defaultPresets[name] = preset;
      });

      radiant.each(self._fenceData.custom_presets, function(name, segments) {
         var preset = self._createPresetObj(name, segments);
         presets.push(preset);
         self._customPresets[name] = preset;
      });

      self.set('presets', presets);
      Ember.run.scheduleOnce('afterRender', self, '_updatePresetTooltips');
   },

   _createPresetObj: function(name, segments) {
      var self = this;
      var preset = {
         name: name,
         segments: self._getProperSegments(segments)
      }
      return preset;
   },

   _getProperSegments: function(segments) {
      var self = this;
      var presetSegments = [];
      radiant.each(segments, function(_, segment) {
         var result = self._getProperSegment(segment.uri, segment.enabled);
         if (result) {
            presetSegments.push(result);
         }
      });
      return presetSegments;
   },

   _getProperSegment: function(uri, enabled) {
      var self = this;
      var lookup = self._segments[uri];
      if (lookup) {
         var presetSegment = radiant.shallow_copy(lookup);
         presetSegment.enabled = enabled;
         return presetSegment;
      }
   },

   _loadConfigSegments: function() {
      var self = this;
      var segments = self._fenceData.selected_segments;
      if (segments) {
         self._setCurrentSegments(self._getProperSegments(segments));
      }
      else {
         self._loadPreset({default: true, name: 'wood1'});
      }
   },

   _updateAvailability: function() {

   },

   _updateAllSegmentTooltips: function() {
      // this function is run only at the beginning to set up dynamic tooltips for all the possible segments in the palette window
      var self = this;
      self.$('.segmentDiv').each(function() {
         self._createSegmentTooltip(self, $(this));
      });
   },

   _updateSegmentTooltips: function() {
      var self = this;
      self.$('.fenceSegmentBtn').each(function() {
         self._createSegmentTooltip(self, $(this), 1000);
      });
      self.$('.toggleSegmentBtn').each(function() {
         var $el = $(this);
         App.tooltipHelper.createDynamicTooltip($el , function () {
            var enabledStr = $el.hasClass('enabled') ? 'segment_enabled' : 'segment_disabled';
            return $(App.tooltipHelper.createTooltip(
               i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.title'),
               i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.' + enabledStr + '.description')));
         }, {delay: 500});
      });
   },

   _createSegmentTooltip: function(self, $el, delay) {
      var uri = $el.data('uri');
      var segment = self._segments[uri];
      App.tooltipHelper.createDynamicTooltip($el, function () {
         var crafterRequirement = self._getCrafterRequirementText(uri);
         return $(App.tooltipHelper.createTooltip(i18n.t(segment.display_name), i18n.t(segment.description), crafterRequirement));
      }, {delay: delay});
   },

   _getCrafterRequirementText: function(uri) {
      // show crafter icon and level required (if it can be crafted), with formatting based on meeting requirements
      return null;
   },

   _updatePresetTooltips: function() {
      var self = this;
      self.$('.presetRow').each(function() {
         var name = $(this).data('name');
         var isDefault = $(this).hasClass('default');
         var preset = self._getPreset(name, isDefault);
         App.tooltipHelper.createDynamicTooltip($(this).find('.presetPreview'), function () {
            // maybe work in the crafting requirements to this tooltip (e.g., 3/4 craftable, requires [Mason] Lvl 2)
            return preset.default ? i18n.t('stonehearth_ace:ui.game.fence_mode.presets.' + name) : name;
         });

         // $(this).find('.presetSegmentImg').each(function() {
         //    self._createSegmentTooltip(self, $(this));
         // });

         $(this).find('.loadPreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.load_preset.title')));
            });
         });
         $(this).find('.savePreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(
                  i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.save_preset.title'),
                  i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.save_preset.description')));
            });
         });
         $(this).find('.deletePreset').each(function() {
            App.tooltipHelper.createDynamicTooltip($(this), function () {
               return $(App.tooltipHelper.createTooltip(
                  i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.delete_preset.title'),
                  i18n.t('stonehearth_ace:ui.game.fence_mode.buttons.delete_preset.description')));
            });
         });
      });
   },

   _togglePresetsVisibility: function(visible) {
      var self = this;
      var presets = self.$('#presetSelection');
      if (visible == false || (!visible && presets.is(':visible'))) {
         presets.hide();
         if (visible != false) {
            // if the user simply closed the presets window
            self.buildFence();
         }
      }
      else {
         self._loadPresets();
         presets.show();
         self.set('canAddSegment', false);
         App.stonehearthClient.deactivateAllTools();
      }
   },

   _loadPreset: function(preset) {
      var self = this;
      var realPreset = self._getPreset(preset.name, preset.default);

      if (realPreset) {
         // slice(0) clones the array
         self._setCurrentSegments(realPreset.segments.slice(0));
         self._updateSegmentsConfig();
         self._togglePresetsVisibility(false);
      }
   },

   _getPreset: function(name, isDefault) {
      var self = this;
      if (isDefault) {
         return self._defaultPresets[name];
      }
      else {
         return self._customPresets[name];
      }
   },

   _setCurrentSegments: function(segments) {
      var self = this;
      self.set('segments', segments);
      Ember.run.scheduleOnce('afterRender', self, '_updateSegmentTooltips');
      self.buildFence();
   },

   buildFence: function() {
      var self = this;

      var curSegments = self.get('segments');
      if (!curSegments) {
         App.stonehearthClient.deactivateAllTools();
         return;
      }

      var fencePieces = [];
      curSegments.forEach(segment => {
         if (segment.enabled) {
            fencePieces.push(segment.uri);
         }
      });

      if (fencePieces.length < 1) {
         App.stonehearthClient.deactivateAllTools();
         return;
      }

      var curTip = App.stonehearthClient._currentTip;
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_description',
         {i18n: true});
      self._recallingTool = tip == curTip;

      var toolFn;
      toolFn = function() {
         return radiant.call('stonehearth_ace:choose_fence_location_command', fencePieces)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildFence();
            })
            .fail(function(response) {
               if (!self._recallingTool) {
                  App.stonehearthClient.hideTip(tip);
               }
               self._recallingTool = false;
            });
      };

      return App.stonehearthClient._callTool('buildFence', toolFn);
   },

   _updateSegmentsConfig: function() {
      var self = this;
      var segments = self.get('segments');
      var toSave = [];
      segments.forEach(segment => {
         toSave.push({
            uri: segment.uri,
            enabled: segment.enabled
         })
      });
      stonehearth_ace.updateFenceModeSettings(toSave);
   },

   _updatePresetsConfig: function() {
      var self = this;
      
      //stonehearth_ace.updateFenceModeSettings();
   },

   _showSegmentSelection: function(segment) {
      var self = this;
      if (self._activeSegment == segment) {
         self._activeSegment = null;
         self.$('#segmentSelection').hide();
         self.buildFence();
      }
      else {
         self._activeSegment = segment;
         self._selectSegmentInSelectionWindow(segment.uri);
         var index = Math.max(0, self.get('segments').indexOf(segment));
         self.$('#segmentSelection').css('left', index * 75 + 'px');
         self.$('#segmentSelection').show();
         self.set('canAddSegment', false);
         App.stonehearthClient.deactivateAllTools();
      }
   },

   _selectSegmentInSelectionWindow: function(uri) {
      var self = this;
      var allSegments = self.$('#segmentSelection');
      allSegments.find('.segmentDiv').removeClass('selected');
      allSegments.find('[data-uri="' + uri + '"]').addClass('selected');
   },

   actions: {
      selectSegment: function(segment) {
         var self = this;
         self._showSegmentSelection(segment);
      },

      setSegment: function(newSegmentUri) {
         var self = this;
         self._selectSegmentInSelectionWindow(newSegmentUri);
         if (self._activeSegment) {
            var segments = self.get('segments');
            var newSegments = [];
            var index = segments.indexOf(self._activeSegment);
            for (var i = 0; i < segments.length; i++) {
               var newSegment = self._getProperSegment(index == i ? newSegmentUri : segments[i].uri, index == i || segments[i].enabled);
               newSegments.push(newSegment);
            }
            self._setCurrentSegments(newSegments);
            self._updateSegmentsConfig();
            self._activeSegment = null;
         }
         self.$('#segmentSelection').hide();
      },

      insertSegment: function() {
         var self = this;
         if (self._insertIndex != null) {
            var segments = self.get('segments');
            var newSegments = [];
            for (var i = 0; i < segments.length; i++) {
               var newSegment = self._getProperSegment(segments[i].uri, segments[i].enabled);
               newSegments.push(newSegment);
            }
            var prevSegment = segments[Math.max(0, self._insertIndex - 1)];
            newSegments.splice(self._insertIndex, 0, self._getProperSegment(prevSegment.uri, true));
            self._setCurrentSegments(newSegments);
            self._updateSegmentsConfig();
            self.set('canAddSegment', false);
         }
      },

      toggleSegment: function(segment) {
         var self = this;
         if (segment) {
            Ember.set(segment, 'enabled', !segment.enabled);
            self._updateSegmentsConfig();
            self.buildFence();
         }
      },

      showLoadPreset: function() {
         var self = this;
         self.set('showLoadButtons', true);
         self.set('showSaveButtons', false);
         self._togglePresetsVisibility();
      },

      showSavePreset: function() {
         var self = this;
         self.set('showLoadButtons', false);
         self.set('showSaveButtons', true);
         self._togglePresetsVisibility();
      },

      loadPreset: function(preset) {
         var self = this;
         self._loadPreset(preset);
      },

      savePreset: function(preset) {

      },

      deletePreset: function(segment) {

      }
   }
});
