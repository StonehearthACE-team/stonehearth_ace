App.StonehearthFarmView.reopen({
   _STATUSES: {
      BAD: 'bad',
      POOR: 'poor',
      AVERAGE: 'average',
      OPTIMAL: 'optimal'
   },

   _WATER_LEVEL_ICONS: {
      NONE: 'none',
      SOME: 'little',
      PLENTY: 'plenty',
      EXTRA: 'some'
   },

   _FLOOD_ICONS: {
      DRY: 'dry',
      REQUIRED: 'required',
      FASTER: 'faster',
      SLOWER: 'slower'
   },

   _GROWTH_TIMES: {
      SHORT: 'short',
      FAIR: 'fair',
      LONG: 'long'
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
               var season = o2.current_season.id;
               self.set('_currentSeason', season);
               self._updateStatuses();
            });
      });
   },

   destroy: function() {
      this._super();
      if (this.seasons_trace) {
         this.seasons_trace.destroy();
         this.seasons_trace = null;
      }
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

      var cropProperties = {};
      self._tooltipData = {};

      self.$('#cropProperties').find('.tooltipstered').tooltipster('destroy');
      self.$('#cropStatuses').find('.tooltipstered').tooltipster('destroy');

      if(details.uri) {
         radiant.call('stonehearth_ace:get_growth_preferences_command', details.uri)
            .done(function (response) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }

               var size = field_sv.size;

               var preferredSeasons = [];
               radiant.each(response.preferred_seasons || [], function(_, season) {
                  preferredSeasons.push({
                     name: season,
                     icon: self._IMAGES_DIR + 'property_season_' + season + '.png',
                     tooltipTitle: localizations.season.property_name,
                     tooltip: localizations.season.property_description,
                     i18n_data: { season: localizations.season.values[season] }
                  });
               })
               self._createPreferredSeasonDivs(preferredSeasons);
               cropProperties.preferredSeasons = preferredSeasons;

               var growth_time = response.growth_time;
               var total_growth_time = response.total_growth_time;
               var time_str = total_growth_time.hour > 0 ? localizations.growth_time.days_and_hours : localizations.growth_time.days_only;
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


               var affinities = response.water_affinity;
               var size_mult = self._getSizeMult(size);
               var waterAffinity = {
                  name: 'waterAffinity',
                  tooltipTitle: localizations.water_affinity.property_name
               };
               if (affinities.next_affinity) {
                  waterAffinity.tooltip = localizations.water_affinity.range;
                  waterAffinity.i18n_data = {
                     min_water_level: self._formatWaterValue(affinities.best_affinity.min_water * size_mult),
                     max_water_level: self._formatWaterValue(affinities.next_affinity.min_water * size_mult)
                  };
               }
               else {
                  waterAffinity.tooltip = localizations.water_affinity.min_only;
                  waterAffinity.i18n_data = { min_water_level: self._formatWaterValue(affinities.best_affinity.min_water * size_mult) };
               }
               
               if (affinities.best_affinity.min_water > 0) {
                  waterAffinity.icon = self._IMAGES_DIR + 'property_water_plenty.png';
               }
               else {
                  waterAffinity.icon = self._IMAGES_DIR + 'property_water_none.png';
               }

               cropProperties.waterAffinity = waterAffinity;
               self._setTooltipData(waterAffinity);
               self._createPropertyTooltip(self.$('#waterAffinity'), waterAffinity.name);


               var requireFlooding = response.require_flooding_to_grow;
               var floodingMultiplier = response.flood_period_multiplier;
               var floodPreference = {
                  name: 'floodPreference',
                  tooltipTitle: localizations.flooded.property_name,
                  requireFlooding: requireFlooding,
                  floodingMultiplier: floodingMultiplier
               };
               if (requireFlooding) {
                  floodPreference.icon = self._IMAGES_DIR + 'property_flood_required.png';
                  floodPreference.tooltip = localizations.flooded.requires;
               }
               else if (floodingMultiplier < 1) {
                  floodPreference.icon = self._IMAGES_DIR + 'property_flood_faster.png';
                  floodPreference.tooltip = localizations.flooded.prefers;
               }
               else if (floodingMultiplier > 1) {
                  floodPreference.icon = self._IMAGES_DIR + 'property_flood_slower.png';
                  floodPreference.tooltip = localizations.flooded.prefers_not;
               }

               cropProperties.floodPreference = floodPreference;
               self._setTooltipData(floodPreference);
               self._createPropertyTooltip(self.$('#floodPreference'), floodPreference.name);

               self.set('cropProperties', cropProperties);
               self._updateStatuses();
            });
      }
      else {
         self.set('cropProperties', null);
      }
   }.observes('model.stonehearth:farmer_field.current_crop_details'),

   _updateStatuses: function() {
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
      var num_flooded = field_sv.num_flooded;
      var current_water_level = field_sv.water_level || 0;
      var size_mult = self._getSizeMult(size);
      var effective_water_level = field_sv.effective_water_level;
      
      var status;
      
      var cropStatuses = {};

      status = self._STATUSES.AVERAGE;
      var prefSeasonTooltip = localizations.season.out_of_season;
      for (i = 0; i < cropProperties.preferredSeasons.length; i++) {
         if (cropProperties.preferredSeasons[i].name == season) {
            status = self._STATUSES.OPTIMAL;
            prefSeasonTooltip = localizations.season.in_season;
            break;
         }
      }

      var currentSeason = {
         name: season,
         icon: self._IMAGES_DIR + 'property_season_' + season + '.png',
         status: status,
         tooltipTitle: localizations.season.status_name,
         tooltip: prefSeasonTooltip,
         i18n_data: localizations.season.values[season]
      };

      cropStatuses.currentSeason = currentSeason;
      self._setTooltipData(currentSeason);
      self._createPropertyTooltip(self.$('#currentSeason'), currentSeason.name);
      self._applyStatus(self.$('#currentSeason'), status);


      var level_icon;
      switch (effective_water_level) {
         case levels.NONE:
            level_icon = self._WATER_LEVEL_ICONS.NONE;
            status = self._STATUSES.POOR;
            break;
         case levels.SOME:
            level_icon = self._WATER_LEVEL_ICONS.SOME;
            status = self._STATUSES.AVERAGE;
            break;
         case levels.PLENTY:
            level_icon = self._WATER_LEVEL_ICONS.PLENTY;
            status = self._STATUSES.OPTIMAL;
            break;
         case levels.EXTRA:
            level_icon = self._WATER_LEVEL_ICONS.EXTRA;
            status = self._STATUSES.AVERAGE;
      }

      var currentWaterLevel = {
         name: 'currentWaterLevel',
         icon: self._IMAGES_DIR + 'property_water_' + level_icon + '.png',
         status: status,
         tooltipTitle: localizations.water_affinity.status_name,
         tooltip: localizations.water_affinity.current_level,
         i18n_data: { current_water_level: self._formatWaterValue(current_water_level * size_mult) }
      };

      cropStatuses.currentWaterLevel = currentWaterLevel;
      self._setTooltipData(currentWaterLevel);
      self._createPropertyTooltip(self.$('#currentWaterLevel'), currentWaterLevel.name);
      self._applyStatus(self.$('#currentWaterLevel'), status);


      status = self._STATUSES.AVERAGE;
      var flood_icon = self._FLOOD_ICONS.DRY;
      if (cropProperties.floodPreference.requireFlooding) {
         if (num_flooded < num_crops) {
            if (num_flooded == 0) {
               status = self._STATUSES.BAD;
            }
            else {
               status = self._STATUSES.POOR;
            }
         }
         else {
            status = self._STATUSES.OPTIMAL;
            flood_icon = self._FLOOD_ICONS.REQUIRED;
         }
      }
      else if (cropProperties.floodPreference.floodingMultiplier < 1) {
         if (num_flooded < num_crops) {
            status = self._STATUSES.POOR;
         }
         else {
            status = self._STATUSES.OPTIMAL;
            flood_icon = self._FLOOD_ICONS.FASTER;
         }
      }
      else if (cropProperties.floodPreference.floodingMultiplier > 1) {
         if (num_flooded > 0) {
            status = self._STATUSES.POOR;
            flood_icon = self._FLOOD_ICONS.SLOWER;
         }
         else {
            status = self._STATUSES.OPTIMAL;
         }
      }

      var currentFlooded = {
         name: 'currentFlooded',
         icon: self._IMAGES_DIR + 'property_flood_' + flood_icon + '.png',
         status: status,
         tooltipTitle: localizations.flooded.status_name,
         tooltip: localizations.flooded.current_amount,
         i18n_data: {
            flooded_status: 'text-' + status,
            num_flooded: num_flooded,
            num_crops: num_crops
         }
      };

      cropStatuses.currentFlooded = currentFlooded;
      self._setTooltipData(currentFlooded);
      self._createPropertyTooltip(self.$('#currentFlooded'), currentFlooded.name);
      self._applyStatus(self.$('#currentFlooded'), status);


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


      // growth time is an approximation based on the number of growth time modifiers, not their magnitudes
      // so we wait until after our calculations on those other fields to determine this
      status = self._STATUSES.AVERAGE;
      var growthTime = self._GROWTH_TIMES.FAIR;
      var growthTimeTooltip = localizations.growth_time.normal;
      var numPositive = 0;
      var numNegative = 0;

      if (currentSeason.status != self._STATUSES.OPTIMAL) {
         numNegative++;
      }
      switch (currentWaterLevel.status) {
         case self._STATUSES.POOR:
            numNegative++;
            break;
         case self._STATUSES.OPTIMAL:
            numPositive++;
            break;
      }
      switch (currentFlooded.status) {
         case self._STATUSES.BAD:
            numNegative += 2;
            break;
         case self._STATUSES.POOR:
            numNegative++;
            break;
         case self._STATUSES.OPTIMAL:
            numPositive++;
            break;
      }

      if (numPositive > numNegative) {
         growthTime = self._GROWTH_TIMES.SHORT;
         growthTimeTooltip = localizations.growth_time.shorter;
         status = self._STATUSES.OPTIMAL;
      }
      else if (numPositive < numNegative) {
         growthTime = self._GROWTH_TIMES.LONG;
         growthTimeTooltip = localizations.growth_time.longer;
         status = self._STATUSES.POOR;
      }

      var relativeGrowthTime = {
         name: 'relativeGrowthTime',
         icon: self._IMAGES_DIR + 'property_growth_time_' + growthTime + '.png',
         status: status,
         tooltipTitle: localizations.growth_time.status_name,
         tooltip: growthTimeTooltip
      };

      cropStatuses.relativeGrowthTime = relativeGrowthTime;
      self._setTooltipData(relativeGrowthTime);
      self._createPropertyTooltip(self.$('#relativeGrowthTime'), relativeGrowthTime.name);
      self._applyStatus(self.$('#relativeGrowthTime'), status);


      self.set('cropStatuses', cropStatuses);

   }.observes('model.stonehearth:farmer_field'),

   _getSizeMult: function(size) {
      // see ace_farmer_field_component.lua:_on_water_volume_changed() for this calculation
      return 4/11 * Math.ceil(size.x / 2) * size.y;
   },

   _formatWaterValue: function(value) {
      return Math.round(value * 10) / 10;
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
               var displayNameTranslated = tooltipData.tooltipTitle && i18n.t(tooltipData.tooltipTitle, tooltipData.i18n_data);
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

   isFallow: function() {
      return this.get('cropProperties') == null;
   }.property('cropProperties')
});
