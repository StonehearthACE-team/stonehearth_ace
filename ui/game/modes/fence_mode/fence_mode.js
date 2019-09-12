App.AceBuildFenceModeView = App.View.extend({
   templateName: 'fenceMode',
   closeOnEsc: false,
   modal: false,

   dismiss: function() {
      this.hide();
   },

   show: function() {
      var self = this;
      self._super();
      
      self._loadSegments();
      self._loadPresets();
      self.buildFence();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self._fenceData = stonehearth_ace.getFenceModeData();

      App.jobController.addChangeCallback('fence_mode', function() {
         self._updateAvailability();
      }, true);
   },

   willDestroyElement: function() {
      App.jobController.removeChangeCallback('fence_mode');
   },

   _loadSegments: function() {
      var self = this;
      var segments = [];
      self._segments = {};

      radiant.each(self._fenceData.types, function(uri, enabled) {
         if (enabled) {
            var catalogData = App.catalog.getCatalogData(uri);
            if (catalogData) {
               var segment = {
                  uri: uri,
                  length: catalogData.fence_length,
                  icon: catalogData.icon,
                  display_name: catalogData.display_name,
                  description: catalogData.description
               };
               self._segments[uri] = segment;
               segments.push(segment);
            }
         }
      });

      self.set('allSegments', segments);
      Ember.run.scheduleOnce('afterRender', self, '_updateSegmentTooltips');
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
      var presetSegments = [];
      radiant.each(segments, function(_, segment) {
         var lookup = self._segments[segment.uri];
         if (lookup) {
            var presetSegment = radiant.shallow_copy(lookup);
            presetSegment.enabled = segment.enabled;
            presetSegments.push(presetSegment);
         }
      });
      var preset = {
         name: name,
         segments: presetSegments
      }
      return preset;
   },

   _updateAvailability: function() {

   },

   _updateSegmentTooltips: function() {

   },

   _updatePresetTooltips: function() {

   },

   _togglePresetsVisibility: function(visible) {
      var self = this;
      var presets = self.$('#presetSelection');
      if (visible == false || (!visible && presets.is(':visible'))) {
         presets.hide();
      }
      else {
         self._loadPresets();
         presets.show();
      }
   },

   _loadPreset: function(preset) {
      var self = this;
      var realPreset;
      if (preset.default) {
         realPreset = self._defaultPresets[preset.name];
      }
      else {
         realPreset = self._customPresets[preset.name];
      }

      if (realPreset) {
         // slice(0) clones the array; whenever we modify individual segments then we'll want to recreate the objects instead of just modifying them
         // because Ember is probably still hanging onto references of the originals in the preset list
         self.set('segments', realPreset.segments.slice(0));
         self._togglePresetsVisibility(false);
         self.buildFence();
      }
   },

   buildFence: function() {
      var self = this;

      var curSegments = self.get('segments');
      if (!curSegments) {
         return;
      }

      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_fence.tip_description',
         {i18n: true});

      return App.stonehearthClient._callTool('buildFence', function() {
         var fencePieces = [];
         curSegments.forEach(segment => {
            if (segment.enabled) {
               fencePieces.push(segment.uri);
            }
         });
         return radiant.call('stonehearth_ace:choose_fence_location_command', fencePieces)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               self.buildFence();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   },

   actions: {
      selectSegment: function(segment) {

      },

      toggleSegment: function(segment) {

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
         this._loadPreset(preset);
      },

      savePreset: function(preset) {

      },

      deletePreset: function(segment) {

      },

      setSegment: function(newSegmentUri) {

      }
   }
});
