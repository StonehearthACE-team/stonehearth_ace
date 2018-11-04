App.StonehearthFarmView.reopen({
   _selectedCropUpdated: function() {
      // when a crop is selected, update the details info panel
      var self = this;
      var field_sv = self.get('model.stonehearth:farmer_field') 
      var details = field_sv.current_crop_details || {};
      if (details.preferred_seasons) {
         details.preferred_seasons = _.map(details.preferred_seasons, i18n.t).join(', ');
      }
      self.set('current_crop_details', details);

      if (details.uri) {
         radiant.call('stonehearth_ace:get_growth_preferences_command', details.uri)
            .done(function (response) {
               var size = field_sv.size;
               var water_level = field_sv.water_level || 0;
               var affinities = response.water_affinity;
               // see ace_farmer_field_component.lua:_on_water_volume_changed() for this calculation
               var size_mult = 4/11 * Math.ceil(size.x / 2) * size.y;
               var water_affinity = {};
               if (affinities.next_affinity) {
                  water_affinity.description = 'stonehearth_ace:ui.game.zones_mode.farm.water_affinity_range';
                  water_affinity.i18n_data = {min: Math.round(affinities.best_affinity.min_water * size_mult),
                                              max: Math.round(affinities.next_affinity.min_water * size_mult),
                                              water_level: water_level};
               }
               else {
                  water_affinity.description = 'stonehearth_ace:ui.game.zones_mode.farm.water_affinity_min_only';
                  water_affinity.i18n_data = {min: Math.round(affinities.best_affinity.min_water * size_mult),
                                              water_level: water_level};
               }

               self.set('water_affinity', water_affinity);
            });
      }
   }.observes('model.stonehearth:farmer_field.current_crop_details')
});
