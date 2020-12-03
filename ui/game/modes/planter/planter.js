App.AceHerbalistPlanterView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'acePlanter',
   closeOnEsc: true,
   _currentCropType: null,

   components: {
      "stonehearth:storage" : {},
      "stonehearth:expendable_resources": {},
      "stonehearth_ace:herbalist_planter" : {},
   },

   init: function() {
      this._super();
      var self = this;

      // we do this so that icons can be specified with the "file(...)" syntax in the json instead of needing absolute paths
      // also because we're not saving the data in the component _sv
      radiant.call('stonehearth_ace:get_all_herbalist_planter_data')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var data = response.data;
            // also index all the crops by seed
            // and go ahead and get all the localization done ahead of time
            var seed_index = {};
            radiant.each(data.crops, function(crop, cropData) {
               if (cropData.seed_uri) {
                  seed_index[cropData.seed_uri] = crop;
               }
               cropData.description = i18n.t(cropData.description);
               cropData.display_name = i18n.t(cropData.display_name);
            });
            data.no_crop.description = i18n.t(data.no_crop.description);
            data.no_crop.display_name = i18n.t(data.no_crop.display_name);

            data.seed_index = seed_index;
            self.set('allCropData', data);
            self._updateAvailableSeeds();
         });
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:usable_item_tracker')
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            self._playerInventoryTrace = new StonehearthDataTrace(response.tracker, {})
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self._inventoryTrackingData = response.tracking_data;
                  self._updateAvailableSeeds();
               });
         });

      self.$('#enableHarvestCheckbox').change(function() {
         var planter = self.get('model.stonehearth_ace:herbalist_planter');
         radiant.call_obj(planter && planter.__self, 'set_harvest_enabled_command', this.checked);
      });

      // tooltips
      App.guiHelper.addTooltip(self.$('#enableHarvest'), 'stonehearth_ace:ui.game.herbalist_planter.harvest_crop_description');

      App.tooltipHelper.createDynamicTooltip(self.$('#produces'), function () {
         var quality = self.get('tendQuality');
         var tooltipString = quality ? i18n.t('stonehearth_ace:ui.game.herbalist_planter.quality.quality-' + quality) : '';
         return $(App.tooltipHelper.createTooltip('', tooltipString));
      });

      self._updateTooltip();
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');

      this._super();
   },

   _updateAvailableSeeds: $.throttle(250, function() {
      var self = this;
      var allCropData = self.get('allCropData');
      if (!allCropData || !self._inventoryTrackingData) {
         return;
      }

      var availableSeeds = {}
      radiant.each(self._inventoryTrackingData, function (uri, uri_entry) {
         var rootUri = uri_entry.canonical_uri || uri;
         var crop = allCropData.seed_index[rootUri];
         if (crop && uri_entry.count > 0) {
            var bestQuality = 1;
            radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
               if (item.count > 0 && item_quality_key > bestQuality) {
                  bestQuality = item_quality_key;
               }
            });
            availableSeeds[crop] = bestQuality;
         }
      });

      self._availableSeeds = availableSeeds;
      if (self.palette) {
         self.palette.updateAvailableSeeds(availableSeeds);
      }
   }),

   _planterCropTypeChange: function() {
      var self = this;

      var allCropData = self.get('allCropData');
      var currentCropType = self.get('model.stonehearth_ace:herbalist_planter.current_crop');
      var plantedCropType = self.get('model.stonehearth_ace:herbalist_planter.planted_crop');

      self._currentCropType = currentCropType;
      self._plantedCropType = plantedCropType;

      // if (!plantedCropType) {
      //    self._showPlanterTypePalette();
      //    return;
      // }

      var currentCropData = null;
      var plantedCropData = null;
      if (allCropData) {
         plantedCropData = allCropData.crops && plantedCropType && allCropData.crops[plantedCropType] || allCropData.no_crop;
         currentCropData = currentCropType != plantedCropType && (allCropData.crops && currentCropType && allCropData.crops[currentCropType] || allCropData.no_crop) || null;
      }

      self.set('plantedCropData', plantedCropData);
      self.set('currentCropData', currentCropData);
   }.observes('allCropData', 'model.stonehearth_ace:herbalist_planter.planted_crop', 'model.stonehearth_ace:herbalist_planter.current_crop'),

   _updateTooltip: function() {
      var self = this;
      var produces = self.get('model.stonehearth_ace:herbalist_planter.num_products') || 0;
      var bonus_items = self.get('model.stonehearth:storage.num_items') || 0;
      
      self.set('produces', produces + (produces && bonus_items ? ' (+)' : ''));
   }.observes('model.stonehearth:storage.num_items'),

   _updateTendQuality: function() {
      var self = this;
      var tendQuality = self.get('model.stonehearth:expendable_resources.resources.tend_quality');
      var maxTendQuality = self.get('maxTendQuality');

      if (tendQuality != null && maxTendQuality != null) {
         tendQuality = Math.max(1, Math.min(maxTendQuality, Math.floor(tendQuality)));
         self.set('tendQuality', tendQuality);
         self.set('tendQualityClass', 'quality' + tendQuality);
      }
      else {
         self.set('tendQuality', null);
         self.set('tendQualityClass', null);
      }
   }.observes('model.stonehearth:expendable_resources.resources.tend_quality', 'maxTendQuality'),

   _updateMaxTendQuality: function() {
      var self = this;
      var playerId = self.get('model.player_id');
      if (playerId) {
         radiant.call('stonehearth_ace:has_guildmaster_town_bonus', playerId)
            .done(function(response) {      
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }

               self.set('maxTendQuality', response.has_guildmaster ? 4 : 3);
            });
      }
      else {
         self.set('maxTendQuality', null);
      }
   }.observes('model.uri'),

   _harvestEnabledChanged: function() {
      var self = this;
      var harvestCrop = self.get('model.stonehearth_ace:herbalist_planter.harvest_enabled');
      self.$('#enableHarvestCheckbox').prop('checked', harvestCrop);
   }.observes('model.stonehearth_ace:herbalist_planter.harvest_enabled'),

   _showPlanterTypePalette: function() {
      if (!this.palette) {
         var planterComponent = this.get('model.stonehearth_ace:herbalist_planter');
         this.palette = App.gameView.addView(App.AcePlanterTypePaletteView, {
            planter: planterComponent && planterComponent.__self,
            planter_view: this,
            planter_data: this.get('allCropData'),
            allowed_crops: planterComponent.allowed_crops,
            available_seeds: this._availableSeeds
         });
      }
   },

   actions :  {
      chooseCropTypeLinkClicked: function() {
         this._showPlanterTypePalette();
      },
   },
   
   destroy: function() {
      if (this.palette) {
         this.palette.destroy();
         this.palette = null;
      }
      if (this._playerInventoryTrace) {
         this._playerInventoryTrace.destroy();
         this._playerInventoryTrace = null;
      }
      this._super();
   },
});

App.AcePlanterTypePaletteView = App.View.extend({
   templateName: 'acePlanterTypePalette',
   modal: true,

   didInsertElement: function() {
      this._super();
      var self = this;

      var cropDataArray = [];

      var allowed_crops = self.allowed_crops;
      radiant.each(self.planter_data.crops, function(key, data) {
         if (allowed_crops[key]) {
            var planterData = {
               type: key,
               icon: data.icon,
               level: Math.max(0, data.level || 0),
               display_name: data.display_name,
               description: data.description
            }
            if (self.available_seeds) {
               var bestQuality = self._getAvailableSeedQuality(self.available_seeds, key);
               planterData.bestQuality = bestQuality;
               planterData.bestQualityClass = 'quality' + bestQuality;
            }
            cropDataArray.push(planterData);
         }
      });

      // add no_crop only if it's not explicitly disallowed or there are no crops allowed for the planter
      if (allowed_crops.no_crop !== false || cropDataArray.length < 1) {
         var no_crop = self.planter_data.no_crop;
         cropDataArray.push({
            type: 'no_crop',
            icon: no_crop.icon,
            level: -1,
            display_name: no_crop.display_name,
            description: no_crop.description,
         });
      }

      cropDataArray.sort(self.available_seeds ? self._sortWithQuality : self._sortWithoutQuality);
      self.set('cropTypes', cropDataArray);
      //self.updateAvailableSeeds(self.available_seeds);

      self.$().on( 'click', '[cropType]', function() {
         var cropType = $(this).attr('cropType');
         if (cropType) {
            if (cropType == 'no_crop') {
               cropType = null;
            }
            radiant.call_obj(self.planter, 'set_current_crop_command', cropType);
         }
         self.destroy();
      });
   },

   updateAvailableSeeds: function(availableSeeds) {
      var self = this;
      if (availableSeeds) {
         var cropTypes = self.get('cropTypes');
         radiant.each(cropTypes, function(i, data) {
            var bestQuality = self._getAvailableSeedQuality(availableSeeds, data.type);
            Ember.set(data, 'bestQuality', bestQuality);
            Ember.set(data, 'bestQualityClass', 'quality' + bestQuality);
         });
         cropTypes.sort(self._sortWithQuality);
      }
   },

   _getAvailableSeedQuality: function(availableSeeds, cropType) {
      return cropType == 'no_crop' ? 1 : availableSeeds[cropType] || 0;
   },

   _sortWithoutQuality: function(a, b) {
      if (a.level < b.level) {
         return -1;
      }
      else if (a.level > b.level) {
         return 1;
      }
      else if (a.display_name < b.display_name) {
         return -1;
      }
      else if (a.display_name > b.display_name) {
         return 1;
      }
      else {
         return 0;
      }
   },

   _sortWithQuality: function(a, b) {
      if (Math.sign(a.bestQuality) > Math.sign(b.bestQuality)) {
         return -1;
      }
      else if (Math.sign(a.bestQuality) < Math.sign(b.bestQuality)) {
         return 1;
      }
      else if (a.level > b.level) {
         return a.bestQuality ? -1 : 1;
      }
      else if (a.level < b.level) {
         return a.bestQuality ? 1 : -1;
      }
      else if (a.bestQuality > b.bestQuality) {
         return -1;
      }
      else if (a.bestQuality < b.bestQuality) {
         return 1;
      }
      else if (a.display_name < b.display_name) {
         return -1;
      }
      else if (a.display_name > b.display_name) {
         return 1;
      }
      else {
         return 0;
      }
   },

   willDestroyElement: function() {
      this.$().off('click', '[cropType]');
      this._super();
   },

   destroy: function() {
      if (this.planter_view) {
         this.planter_view.palette = null;
      }
      this._super();
   }
});
