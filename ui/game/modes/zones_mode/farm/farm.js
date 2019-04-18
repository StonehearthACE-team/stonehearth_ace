App.StonehearthFarmView.reopen({
   _STATUSES: {
      BAD: 'bad',
      POOR: 'poor',
      AVERAGE: 'average',
      OPTIMAL: 'optimal'
   },

   _WATER_LEVEL_ICONS: {
      NONE: 'none',
      LOW: 'little',
      MEDIUM: 'some',
      HIGH: 'quite',
      VERY_HIGH: 'plenty',
		EXCESS: 'excess'
   },

   _LIGHT_LEVEL_ICONS: {
      NONE: 'none',
      LOW: 'low',
      MEDIUM: 'medium',
      HIGH: 'high',
      VERY_HIGH: 'very_high',
		EXCESS: 'extreme'
   },

   _FLOOD_ICONS: {
      DRY: 'dry',
      REQUIRED: 'required',
      FASTER: 'faster',
      SLOWER: 'slower',
      DRY_SLOWER: 'dry_slower',
      DRY_STOPPED: 'dry_no_growth',
      FROZEN: 'frozen'
   },

   _GROWTH_TIMES: {
      SHORT: 'short',
      FAIR: 'fair',
      LONG: 'long',
      SHORTER: 'positive_modifiers',
      NORMAL: 'average_modifiers',
      LONGER: 'negative_modifiers'
   },

   _FERTILIZER: {
      NONE: 'none',
      LOW: 'low',
      HIGH: 'high',
      URI: 'uri'
   },

   _IMAGES_DIR: '/stonehearth_ace/ui/game/modes/zones_mode/farm/images/',

   init: function() {
      var self = this;
      self._super();

      self.set('propertyLocalizations', null);
      var localizations;
      // get the property localization keys (allows other seasons/properties to be mixed in)
      $.getJSON('/stonehearth_ace/ui/data/farm_properties.json', function(data) {
         localizations = data || {};
         self.set('propertyLocalizations', localizations);
      });

      radiant.call('stonehearth:get_service', 'seasons')
      .done(function (o) {
         self.seasons_trace = radiant.trace(o.result)
            .progress(function (o2) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               self.set('_currentSeason', o2.current_season);
               self._updateStatuses();
            });
      });
   },

   willDestroyElement: function() {
      var self = this;

      clearInterval(self._periodicFertilizerUpdate);

      this._fertilizerPalette.stonehearthItemPalette('destroy');
      this._fertilizerPalette = null;

      App.tooltipHelper.removeDynamicTooltip(self.$('.cropProperty'));

      this._super();
   },

   destroy: function() {
      this._super();
      if (this.seasons_trace) {
         this.seasons_trace.destroy();
         this.seasons_trace = null;
      }
      if (this.farmer_info_trace) {
         this.farmer_info_trace.destroy();
         this.farmer_info_trace = null;
      }
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      var filterFn = function(k, v) {
         if (v.materials) {
            for (i = 0; i < v.materials.length; i++) {
               if (v.materials[i].toLowerCase() == 'fertilizer') {
                  return true;
               }
            }
         }
         return false;
      }

      self._catalogFertilizers = App.catalog.getFilteredCatalogData('fertilizers', filterFn);
      
      self._fertilizerPalette = self.$('#fertilizerPalette').stonehearthItemPalette({
         cssClass: 'fertilizerItem',
         showZeroes: true,
         skipCategories: true,
         sortField: 'net_worth',
         click: function(item) {
            self._setFertilizerSetting(self._FERTILIZER.URI, item.attr('uri'));
         }
      });

      self.$('#fertilizerNone').on('click', function() {
         self._setFertilizerSetting(self._FERTILIZER.NONE);
      });
      self.$('#fertilizerLow').on('click', function() {
         self._setFertilizerSetting(self._FERTILIZER.LOW);
      });
      self.$('#fertilizerHigh').on('click', function() {
         self._setFertilizerSetting(self._FERTILIZER.HIGH);
      });

      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth_ace:fertilizer_tracker')
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            var itemTraces = {
               "tracking_data" : { '*': { 'stonehearth:stacks': {}}}
            };

            if (!self._fertilizerPalette) {
               return;
            }
            self._playerInventoryTrace = new StonehearthDataTrace(response.tracker, itemTraces)
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self._inventoryFertilizerData = response.tracking_data;
                  self._updateFertilizers();
               });
            
            self._periodicFertilizerUpdate = setInterval(self._updateFertilizers, 500, self);
         })
         .fail(function(response) {
            console.error(response);
         });
   },

   _updateFertilizers: $.throttle(250, function (self) {
      self = self || this;
      if (!self.$() || !self._fertilizerPalette) return;

      var fertilizerDataByUri = {};
      var fertilizerData = {};
      // merge iconic and root entities and all qualities
      radiant.each(self._catalogFertilizers, function (uri, fertilizer) {
         var fertilizer_copy = radiant.shallow_copy(fertilizer);
         fertilizer_copy.uri = uri;
         fertilizer_copy.item_quality = '1';
         fertilizer_copy.count = 0;

         var key = fertilizer_copy.uri + App.constants.item_quality.KEY_SEPARATOR + '1';
         fertilizerData[key] = fertilizer_copy;
         fertilizerDataByUri[uri] = fertilizer_copy;
      });

      radiant.each(self._inventoryFertilizerData, function (id, item) {
         var uri = item.uri;
         var fertilizer = fertilizerDataByUri[uri];
         if (fertilizer) {
            var stacks = item['stonehearth:stacks'];
            if (stacks && stacks.stacks) {
               fertilizer.count += stacks.stacks;
            }
         }
      });

      self._fertilizerPalette.stonehearthItemPalette('updateItems', fertilizerData);
      self._updateFertilizerSelection();
   }),

   _setFertilizerSetting: function(setting, uri) {
      var self = this;

      var preference = {};
      switch (setting) {
         case self._FERTILIZER.URI:
            preference.uri = uri;
            break;
         case self._FERTILIZER.NONE:
            preference.quality = 0;
            break;
         case self._FERTILIZER.LOW:
            preference.quality = -1;
            break;
         case self._FERTILIZER.HIGH:
            preference.quality = 1;
            break;
      }

      radiant.call('stonehearth_ace:set_farm_fertilizer_preference', self.get('uri'), preference);
   },

   _updateFertilizerSetting: function() {
      var self = this;
      var fertilizer_preference = self.get('model.stonehearth:farmer_field.fertilizer_preference') || {};
      var quality = fertilizer_preference.quality
      var uri = fertilizer_preference.uri;
      var current = self.get('fertilizerSetting');

      var newSetting = self._FERTILIZER.HIGH;
      if (quality != undefined) {
         if (quality == 0) {
            newSetting = self._FERTILIZER.NONE;
         }
         else if (quality < 0) {
            newSetting = self._FERTILIZER.LOW;
         }
         else {
            newSetting = self._FERTILIZER.HIGH;
         }
      }

      if (uri != undefined) {
         newSetting = self._FERTILIZER.URI;
      }

      if (newSetting == self._FERTILIZER.URI) {
         if (newSetting != uri) {
            self.set('fertilizerSetting', uri);
         }
      }
      else {
         if (newSetting != current) {
            self.set('fertilizerSetting', newSetting);
         }
      }
   }.observes('model.stonehearth:farmer_field.fertilizer_preference'),

   _updateFertilizerSelection: function() {
      var self = this;
      self.$('#fertilizerSettings input').prop('checked', false);
      self._clearUriFertilizerSelection();

      var setting = self.get('fertilizerSetting');
      switch (setting) {
         case self._FERTILIZER.NONE:
            self.$('#fertilizerNoneButton').prop('checked', true);
            break;
         case self._FERTILIZER.LOW:
            self.$('#fertilizerLowButton').prop('checked', true);
            break;
         case self._FERTILIZER.HIGH:
            self.$('#fertilizerHighButton').prop('checked', true);
            break;
         default:
            self.$('#fertilizerPalette').find('[uri="' + setting + '"]').addClass('selected');
            break;
      }
   }.observes('fertilizerSetting'),

   _clearUriFertilizerSelection: function() {
      var self = this;
      self.$('.fertilizerItem').removeClass('selected');
   },

   _selectedCropUpdated: function() {
      var self = this;

      var localizations = self.get('propertyLocalizations');
      if (!localizations) {
         return;
      }
      
      // when a crop is selected, update the details info panel
      var field_sv = self.get('model.stonehearth:farmer_field');
      var details = field_sv.current_crop_details || {};

      if (self._oldURI != details.uri) {
         self._oldURI = details.uri;

         App.tooltipHelper.removeDynamicTooltip(self.$('.cropProperty'));
         self._tooltipData = {};

         if(details.uri) {
            var preferredClimate = details.preferred_climate || 'temperate_staple';
            var climatePrefs = App.constants.climates[preferredClimate];
            self._waterAffinities = self._getBestAffinityRange(App.constants.plant_water_affinity[climatePrefs.plant_water_affinity]);
            self._lightAffinities = self._getBestAffinityRange(App.constants.plant_light_affinity[climatePrefs.plant_light_affinity]);
            
            var cropProperties = self._doUpdateProperties(localizations, field_sv);
            self.set('cropProperties', cropProperties);
            self._updateStatuses();
         }
         else {
            self.set('cropProperties', null);
         }
      }
   }.observes('model.stonehearth:farmer_field.current_crop_details'),

   // this function can be inherited/overridden to add more properties
   _doUpdateProperties: function(localizations, field_sv) {
      var self = this;
      if (self.isDestroyed || self.isDestroying) {
         return;
      }

      var cropProperties = {};
      var details = field_sv.current_crop_details || {};
      var size = field_sv.size;

      var preferredSeasons = [];
      radiant.each(details.preferred_seasons || {}, function(season, season_i18n) {
         preferredSeasons.push({
            name: season,
            icon: stonehearth_ace.getSeasonIcon(season),
            tooltipTitle: localizations.season.property_name,
            tooltip: localizations.season.property_description,
            i18n_data: { season: season_i18n }
         });
      })
      if (preferredSeasons.length < 1) {
         // no preferred seasons
         preferredSeasons.push({
            name: 'any',
            icon: stonehearth_ace.getSeasonIcon('any'),
            tooltipTitle: localizations.season.no_season_title,
            tooltip: localizations.season.no_season_description
         });
      }
      self._createPreferredSeasonDivs(preferredSeasons);
      cropProperties.preferredSeasons = preferredSeasons;

      var growth_time = details.growth_time;
      var total_growth_time = details.total_growth_time;
      var time_str = total_growth_time.day > 0 ? 
            (total_growth_time.hour > 0 ? localizations.growth_time.days_and_hours : localizations.growth_time.days_only) : 
            localizations.growth_time.hours_only;
      var growthTime = {
         name: 'growthTime',
         icon: self._IMAGES_DIR + 'property_growth_time_' + growth_time + '.png',
         tooltipTitle: localizations.growth_time.property_name,
         tooltip: localizations.growth_time[growth_time],
         i18n_data: {
            total_growth_time: i18n.t(time_str, {
               i18n_data: total_growth_time,
               escapeHTML: true
            })
         }
      };

      cropProperties.growthTime = growthTime;
      self._setTooltipData(growthTime);
      self._createPropertyTooltip(self.$('#growthTime'), growthTime.name);


      var affinities = self._waterAffinities;
      // only include water affinity if it applies (i.e., if there's more than one possible affinity level)
      if (affinities.best_affinity && (affinities.best_affinity.min_level > 0 || affinities.next_affinity))
      {
         var size_mult = self._getSizeMult(size);
         var waterAffinity = {
            name: 'waterAffinity',
            tooltipTitle: localizations.water_affinity.property_name,
            icon: self._getWaterIcon(affinities.best_affinity.min_level)
         };
         if (affinities.next_affinity) {
            waterAffinity.tooltip = localizations.water_affinity.range;
            waterAffinity.i18n_data = {
               min_water_level: self._formatFlatValue(affinities.best_affinity.min_level * size_mult),
               max_water_level: self._formatFlatValue(affinities.next_affinity.min_level * size_mult)
            };
         }
         else {
            waterAffinity.tooltip = localizations.water_affinity.min_only;
            waterAffinity.i18n_data = { min_water_level: self._formatFlatValue(affinities.best_affinity.min_level * size_mult) };
         }

         cropProperties.waterAffinity = waterAffinity;
         self._setTooltipData(waterAffinity);
         self._createPropertyTooltip(self.$('#waterAffinity'), waterAffinity.name);


         var floodType = self._FLOOD_ICONS.DRY;
         var floodTooltip = localizations.flooded.prefers_not;
         var requireFlooding = details.require_flooding_to_grow;
         var floodingMultiplier = details.flood_period_multiplier;
         var frozenMultiplier = details.frozen_period_multiplier;
         if (requireFlooding) {
            floodType = self._FLOOD_ICONS.REQUIRED;
            floodTooltip = localizations.flooded.requires;
         }
         else if (floodingMultiplier < 1) {
            floodType = self._FLOOD_ICONS.FASTER;
            floodTooltip = localizations.flooded.prefers;
         }
         else if (floodingMultiplier > 1) {
            floodType = self._FLOOD_ICONS.DRY;
            floodTooltip = localizations.flooded.prefers_not;
         }

         var floodPreference = {
            name: 'floodPreference',
            tooltipTitle: localizations.flooded.property_name,
            requireFlooding: requireFlooding,
            floodingMultiplier: floodingMultiplier,
            frozenMultiplier: frozenMultiplier,
            icon: self._IMAGES_DIR + 'property_flood_' + floodType + '.png',
            tooltip: floodTooltip
         };

         cropProperties.floodPreference = floodPreference;
         self._setTooltipData(floodPreference);
         self._createPropertyTooltip(self.$('#floodPreference'), floodPreference.name);

         self.set('showWater', true);
      }
      else {
         self.set('showWater', false);
      }


      var affinities = self._lightAffinities;
      var lightAffinity = {
         name: 'lightAffinity',
         icon: self._getLightIcon(affinities.best_affinity.min_level),
         tooltipTitle: localizations.light_affinity.property_name,
         min_light_level: affinities.best_affinity.min_level
      };
      if (affinities.next_affinity) {
         lightAffinity.max_light_level = affinities.next_affinity.min_level;
         lightAffinity.tooltip = localizations.light_affinity.range;
         lightAffinity.i18n_data = {
            min_light_level: self._formatPercentValue(affinities.best_affinity.min_level),
            max_light_level: self._formatPercentValue(affinities.next_affinity.min_level)
         };
      }
      else {
         lightAffinity.tooltip = localizations.light_affinity.min_only;
         lightAffinity.i18n_data = { min_light_level: self._formatPercentValue(affinities.best_affinity.min_level) };
      }

      cropProperties.lightAffinity = lightAffinity;
      self._setTooltipData(lightAffinity);
      self._createPropertyTooltip(self.$('#lightAffinity'), lightAffinity.name);

      return cropProperties;
   },

   _updateStatuses: function() {
      var self = this;
      if (self.isDestroyed || self.isDestroying) {
         return;
      }

      var cropStatuses = self._doUpdateStatuses();
      self.set('cropStatuses', cropStatuses);
   }.observes('model.stonehearth:farmer_field'),

   // same as properties, statuses can be added by overriding this function
   _doUpdateStatuses: function() {
      var self = this;
      // properties are needed to properly consider flood preference when indicating num_flooded
      var cropProperties = self.get('cropProperties');
      var localizations = self.get('propertyLocalizations');
      var season = self.get('_currentSeason');
      if (!cropProperties || !localizations || !season) {
         return;
      }

      var levels = App.constants.farming.water_levels;

      var field_sv = self.get('model.stonehearth:farmer_field');
      var size = field_sv.size;
      var num_crops = field_sv.num_crops;
      var num_fertilized = field_sv.num_fertilized;
      var is_flooded = field_sv.flooded;
      var current_water_level = field_sv.humidity_level;
      var size_mult = self._getSizeMult(size);
      var effective_humidity_level = field_sv.effective_humidity_level;
      var current_light_level = field_sv.sunlight_level;
      var growth_time_modifier = field_sv.growth_time_modifier;
      var is_frozen = field_sv.frozen;
      
      var status;
      
      var cropStatuses = {};

      status = self._STATUSES.AVERAGE;
      var prefSeasonTooltip = localizations.season.out_of_season;
      for (i = 0; i < cropProperties.preferredSeasons.length; i++) {
         var name =cropProperties.preferredSeasons[i].name;
         if (name == 'any' || name == season.id) {
            status = self._STATUSES.OPTIMAL;
            prefSeasonTooltip = localizations.season.in_season;
            break;
         }
      }

      var currentSeason = {
         name: season.id,
         icon: stonehearth_ace.getSeasonIcon(season.id),
         status: status,
         tooltipTitle: localizations.season.status_name,
         tooltip: prefSeasonTooltip,
         i18n_data: { season: season.display_name }
      };

      cropStatuses.currentSeason = currentSeason;
      self._setTooltipData(currentSeason);
      self._createPropertyTooltip(self.$('#currentSeason'), currentSeason.name);
      self._applyStatus(self.$('#currentSeason'), status);


      // only include water statuses if water properties are included
      if (cropProperties.waterAffinity)
      {
         switch (effective_humidity_level) {
            case levels.NONE:
               status = self._STATUSES.POOR;
               break;
            case levels.SOME:
               status = self._STATUSES.AVERAGE;
               break;
            case levels.PLENTY:
               status = self._STATUSES.OPTIMAL;
               break;
            case levels.EXTRA:
               status = self._STATUSES.AVERAGE;
         }

         var currentWaterLevel = {
            name: 'currentWaterLevel',
            icon: self._getWaterIcon(current_water_level,
               {
                  min: self._waterAffinities.best_affinity.min_level,
                  max: self._waterAffinities.next_affinity && self._waterAffinities.next_affinity.min_level
               }),
            status: status,
            tooltipTitle: localizations.water_affinity.status_name,
            tooltip: localizations.water_affinity.current_level,
            i18n_data: { current_water_level: self._formatFlatValue(current_water_level * size_mult) }
         };

         cropStatuses.currentWaterLevel = currentWaterLevel;
         self._setTooltipData(currentWaterLevel);
         self._createPropertyTooltip(self.$('#currentWaterLevel'), currentWaterLevel.name);
         self._applyStatus(self.$('#currentWaterLevel'), status);


         status = self._STATUSES.AVERAGE;
         var flood_icon = self._FLOOD_ICONS.DRY;
         var flood_tooltip = localizations.flooded.current_not_flooded;
         if (is_frozen) {
            // frozen status takes precendence over flooding
            flood_tooltip = localizations.frozen.current_frozen;
            flood_icon = self._FLOOD_ICONS.FROZEN;
            if (cropProperties.floodPreference.frozenMultiplier < 1) {
               // unlikely...
               status = self._STATUSES.OPTIMAL;
            }
            else if (cropProperties.floodPreference.frozenMultiplier > 1) {
               status = self._STATUSES.POOR;
            }
         }
         else {
            if (is_flooded) {
               flood_tooltip = localizations.flooded.current_flooded;
            }
            if (cropProperties.floodPreference.requireFlooding) {
               if (!is_flooded) {
                  status = self._STATUSES.BAD;
                  flood_icon = self._FLOOD_ICONS.DRY_STOPPED;
               }
               else {
                  status = self._STATUSES.OPTIMAL;
                  flood_icon = self._FLOOD_ICONS.REQUIRED;
               }
            }
            else if (cropProperties.floodPreference.floodingMultiplier < 1) {
               if (!is_flooded) {
                  status = self._STATUSES.POOR;
                  flood_icon = self._FLOOD_ICONS.DRY_SLOWER;
               }
               else {
                  status = self._STATUSES.OPTIMAL;
                  flood_icon = self._FLOOD_ICONS.FASTER;
               }
            }
            else if (cropProperties.floodPreference.floodingMultiplier > 1) {
               if (is_flooded) {
                  status = self._STATUSES.POOR;
                  flood_icon = self._FLOOD_ICONS.SLOWER;
               }
               else {
                  status = self._STATUSES.OPTIMAL;
               }
            }
            else if (is_flooded) {
               flood_icon = self._FLOOD_ICONS.REQUIRED;
            }
         }

         var currentFlooded = {
            name: 'currentFlooded',
            icon: self._IMAGES_DIR + 'property_flood_' + flood_icon + '.png',
            status: status,
            tooltipTitle: localizations.flooded.status_name,
            tooltip: flood_tooltip,
            i18n_data: {
               flooded_status: 'text-' + status
            }
         };

         cropStatuses.currentFlooded = currentFlooded;
         self._setTooltipData(currentFlooded);
         self._createPropertyTooltip(self.$('#currentFlooded'), currentFlooded.name);
         self._applyStatus(self.$('#currentFlooded'), status);
      }


      if (current_light_level < cropProperties.lightAffinity.min_light_level) {
         status = self._STATUSES.AVERAGE;
      }
      else if(cropProperties.lightAffinity.max_light_level && current_light_level > cropProperties.lightAffinity.max_light_level) {
         status = self._STATUSES.AVERAGE;
      }
      else {
         status = self._STATUSES.OPTIMAL;
      }

      var currentLightLevel = {
         name: 'currentLightLevel',
         icon: self._getLightIcon(current_light_level),
         status: status,
         tooltipTitle: localizations.light_affinity.status_name,
         tooltip: localizations.light_affinity.current_level,
         i18n_data: { current_light_level: self._formatPercentValue(current_light_level) }
      };

      cropStatuses.currentLightLevel = currentLightLevel;
      self._setTooltipData(currentLightLevel);
      self._createPropertyTooltip(self.$('#currentLightLevel'), currentLightLevel.name);
      self._applyStatus(self.$('#currentLightLevel'), status);


      status = self._STATUSES.AVERAGE;
      if (num_fertilized < num_crops) {
         if (num_fertilized == 0) {
            status = self._STATUSES.POOR;
         }
      }
      else if (num_fertilized > 0) {
         status = self._STATUSES.OPTIMAL;
      }

      var currentFertilized = {
         name: 'currentFertilized',
         icon: self._IMAGES_DIR + 'property_fertilizer.png',
         tooltipTitle: localizations.fertilized.status_name,
         tooltip: localizations.fertilized.current_amount,
         i18n_data: {
            fertilized_status: 'text-' + status,
            num_fertilized: num_fertilized,
            num_crops: num_crops
         }
      };

      cropStatuses.currentFertilized = currentFertilized;
      self._setTooltipData(currentFertilized);
      self._createPropertyTooltip(self.$('#currentFertilized'), currentFertilized.name);
      self._applyStatus(self.$('#currentFertilized'), status);


      status = self._STATUSES.AVERAGE;
      var growthTime = self._GROWTH_TIMES.NORMAL;
      var growthTimeTooltip = localizations.growth_time.normal;

      if (currentFlooded && currentFlooded.status == self._STATUSES.BAD) {
         growthTime = self._GROWTH_TIMES.LONGER;
         growthTimeTooltip = localizations.growth_time.stopped;
         status = self._STATUSES.BAD;
      }
      else if (growth_time_modifier <= 0.9) {
         growthTime = self._GROWTH_TIMES.SHORTER;
         growthTimeTooltip = localizations.growth_time.shorter;
         status = self._STATUSES.OPTIMAL;
      }
		else if (growth_time_modifier >= 5) {
         growthTime = self._GROWTH_TIMES.LONGER;
         growthTimeTooltip = localizations.growth_time.too_long;
         status = self._STATUSES.BAD;
      }
      else if (growth_time_modifier >= 1.1) {
         growthTime = self._GROWTH_TIMES.LONGER;
         growthTimeTooltip = localizations.growth_time.longer;
         status = self._STATUSES.POOR;
      }

      var relativeGrowthTime = {
         name: 'relativeGrowthTime',
         icon: self._IMAGES_DIR + 'property_growth_time_' + growthTime + '.png',
         status: status,
         tooltipTitle: localizations.growth_time.status_name,
         tooltip: growthTimeTooltip,
         i18n_data: {
            growth_time_percent: self._formatMultiplierValue(1 / growth_time_modifier)
         }
      };

      cropStatuses.relativeGrowthTime = relativeGrowthTime;
      self._setTooltipData(relativeGrowthTime);
      self._createPropertyTooltip(self.$('#relativeGrowthTime'), relativeGrowthTime.name);
      self._applyStatus(self.$('#relativeGrowthTime'), status);

      return cropStatuses;
   },

   _getSizeMult: function(size) {
      // see ace_farmer_field_component.lua:_on_water_volume_changed() for this calculation
      return 4/11 * Math.ceil(size.x / 2) * size.y;
   },

   _formatFlatValue: function(value) {
      return Math.round(value * 10) / 10;
   },

   _formatPercentValue: function(value) {
      return Math.round(value * 100) + '%';
   },

   _formatMultiplierValue: function(value) {
      return Math.round(Math.abs(1 - value) * 100) + '%';
   },

   _getLightIcon: function(value) {
      var self = this;
      return self._IMAGES_DIR + 'property_sunlight_' + self._getAffinityLevel(self._LIGHT_LEVEL_ICONS, value) + '.png';
   },

   _getWaterIcon: function(value, affinity) {
      var self = this;
      var icon = affinity == null ?
            self._getAffinityLevel(self._WATER_LEVEL_ICONS, value) : self._getRelativeAffinityLevel(self._WATER_LEVEL_ICONS, value, affinity);
      return self._IMAGES_DIR + 'property_water_' + icon + '.png';
   },

   _getAffinityLevel: function(table, value) {
      var level = table.VERY_HIGH;

      if (value < 0.2) {
         level = table.NONE;
      }
      else if (value < 0.4) {
         level = table.LOW;
      }
      else if (value < 0.65) {
         level = table.MEDIUM;
      }
      else if (value < 0.9) {
         level = table.HIGH;
      }

      return level;
   },

   _getRelativeAffinityLevel: function(table, value, affinity) {
      if (value == 0) {
         return table.NONE;
      }
      else if (value < affinity.min) {
         return table.LOW;
      }
      else if (affinity.max && value > affinity.max) {
         return table.EXCESS;
      }
		else if (affinity.max && value == affinity.max) {
         return table.VERY_HIGH;
      }
      else if (affinity.max) {
         return table.HIGH;
      }
      else {
         return table.MEDIUM;
      }
   },

   _getBestAffinityRange: function(table) {
      var result = {};

      for (var i = 0; i < table.length; i++) {
         var level = table[i];
         if (!result.best_affinity || level.period_multiplier < result.best_affinity.period_multiplier) {
            result.best_affinity = level;
            if (i < table.length - 1) {
               result.next_affinity = table[i + 1];
            }
            else {
               delete result.next_affinity;
            }
         }
      }

      return result;
   },

   _applyStatus: function(div, status) {
      var self = this;
      
      // first remove all other statuses
      var classes = [];
      for (var s in self._STATUSES) {
         classes.push('status-' + self._STATUSES[s]);
      }
      div.removeClass(classes.join(' '));

      div.addClass('status-' + status);
   },

   _createPreferredSeasonDivs: function(seasons) {
      var self = this;
      
      var itemEl = self.$('#preferredSeasons');
      itemEl.empty();

      var num = 1;
      radiant.each(seasons, function(_, entry) {
         var img = $('<img>')
            .addClass('cropPropertyImage')
            .attr('src', entry.icon);
         
         var div = $('<div>')
            .addClass('cropProperty')
            .attr('season-id', num)
            .append(img);

         // if (num > 1) {
         //    div.addClass('overlap');
         // }

         var seasonId = 'season-' + num;
         self._setTooltipData(entry, seasonId);

         itemEl.append(div);

         self._createPropertyTooltip(div, seasonId)

         num++;
      });
   },

   _setTooltipData: function(property, name) {
      var self = this;
      name = name || property.name;

      self._tooltipData[name] = {
         tooltipTitle: property.tooltipTitle,
         tooltip: property.tooltip,
         i18n_data: property.i18n_data
      };
   },

   _createPropertyTooltip: function(div, property) {
      var self = this;

      if (!div.hasClass('tooltipstered')) {
         App.tooltipHelper.createDynamicTooltip(div, function() {
            var tooltipData = (self._tooltipData || {})[property];
            if (tooltipData) {
               var displayNameTranslated = tooltipData.tooltipTitle && i18n.t(tooltipData.tooltipTitle, {
                  i18n_data: tooltipData.i18n_data,
                  escapeHTML: true
               });
               var description = tooltipData.tooltip && i18n.t(tooltipData.tooltip, {
                  i18n_data: tooltipData.i18n_data,
                  escapeHTML: true
               });
               var tooltip = App.tooltipHelper.createTooltip(displayNameTranslated, description);
               return $(tooltip);
            }
         });
      }
   },

   // hard-coded for farmers level 3 gaining fertilizer
   // TODO: tie it into some constant somewhere or read in the perk data
   _updatedFarmerJobInfo: function() {
      var self = this;
      if (!self.farmer_info_trace) {
         self.farmer_info_trace = radiant.trace(self.get('farmer_job_info'))
            .progress(function (o) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               self.set('highest_level', o.highest_level);
            });
      }
   }.observes('farmer_job_info'),

   _showFertilizer: function() {
      var self = this;
      self.set('showFertilizer', self.get('highest_level') >= 3);
   }.observes('highest_level'),

   isFallow: function() {
      return this.get('cropProperties') == null;
   }.property('cropProperties')
});
