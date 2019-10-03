App.StonehearthPastureView.reopen({
   init: function() {
      this._super();

      var self = this;

      radiant.call_obj('stonehearth.job', 'get_job_call', 'stonehearth:jobs:shepherd')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            if (response.job_info_object) {
               self._job_info_trace = radiant.trace(response.job_info_object)
               .progress(function (o2) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self.set('shepherd_job_info', o2);
               });
            }
         });
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      // clicking checkboxes
      self.$('#harvestAnimalsCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_pasture_harvest_animals_renewable', self.get('uri'), this.checked);
      })
      self.$('#harvestGrassCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_pasture_harvest_grass', self.get('uri'), this.checked);
      })

      // tooltips
      App.guiHelper.addTooltip(self.$('#maintainAnimalsLabel'), 'stonehearth_ace:ui.game.zones_mode.pasture.maintain_animals_description');
      App.guiHelper.addTooltip(self.$('#harvestAnimals'), 'stonehearth_ace:ui.game.zones_mode.pasture.harvest_animals_renewable_description');
      App.guiHelper.addTooltip(self.$('#harvestGrass'), 'stonehearth_ace:ui.game.zones_mode.pasture.harvest_grass_description');
   },

   willDestroyElement: function() {
      var self = this;
      if (self._maintainSelector) {
         self._maintainSelector.find('.tooltipstered').tooltipster('destroy');
         self._maintainSelector.empty();
      }

      if (self._job_info_trace) {
         self._job_info_trace.destroy();
         self._job_info_trace = null;
      }

      this._super();
   },

   _pastureChanged: function() {
      var self = this;
      var harvestAnimals = self.get('model.stonehearth:shepherd_pasture.harvest_animals_renewable');
      var harvestGrass = self.get('model.stonehearth:shepherd_pasture.harvest_grass');

      self.$('#harvestAnimalsCheckbox').prop('checked', harvestAnimals);
      self.$('#harvestGrassCheckbox').prop('checked', harvestGrass);
   }.observes('model.stonehearth:shepherd_pasture'),

   _pastureAnimalTypeChange: function() {
      var self = this;
      self._super();

      // check if the current animal type has a renewable resource component to it and set 'renewable' accordingly

      var capacity = self.get('capacity');
      var maintain = self.get('model.stonehearth:shepherd_pasture.maintain_animals');
      var renewable = self.get('model.stonehearth:shepherd_pasture.critter_type_has_renewable');

      self.set('renewable', renewable);

      // add custom list selector
      var selector = self._maintainSelector;
      if (selector) {
         selector.find('tooltipster').tooltipster('destroy');
         selector.remove();
      }

      if (capacity) {
         var pastureData = self.get('model.stonehearth:shepherd_pasture.pasture_data');
         var pastureType = self.get('model.stonehearth:shepherd_pasture.pasture_type');
         var min = pastureData[pastureType].min_population || 2;
         var vals = [];
         for (var i = capacity; i >= min; i--) {
            vals.push(i + '');
         }

         var onChanged = function (key, value) {
            var val = parseInt(value.key);
            if (val != NaN) {
               radiant.call('stonehearth_ace:set_pasture_maintain_animals', self.get('uri'), val);
            }
         };

         selector = App.guiHelper.createCustomSelector('pasture_maintainAnimals', vals, onChanged).container;
         App.guiHelper.setListSelectorValue(selector, maintain + '');

         self._maintainSelector = selector;
         self.$('#maintainAnimals').append(selector);
      }
   }.observes('model.stonehearth:shepherd_pasture.pasture_type'),

   _tracedShepherdJobInfo: function() {
      if (this.palette) {
         this.palette.set('highest_level', this.get('shepherd_job_info.highest_level'));
      }
   }.observes('shepherd_job_info.highest_level'),
});

App.StonehearthPastureTypePaletteView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      this.$().off('click', '[pastureType]')
      .on( 'click', '[pastureType]', function() {
         if ($(this).attr('locked')) {
            return;
         }
         var pastureType = $(this).attr('pastureType');
         if (pastureType) {
            radiant.call_obj(self.pasture, 'set_pasture_type_command', pastureType);
         }
         self.destroy();
      });

      radiant.each(self.get('pastureTypes'), function(_, data) {
         var pasture_data = self.pasture_data[data.type]
         Ember.set(data, 'ordinal', pasture_data.ordinal);
         Ember.set(data, 'level_requirement', pasture_data.level_requirement);
      });
      self.set('highest_level', self.pasture_view.get('shepherd_job_info.highest_level'));
      self._updateLockedAnimals();
   },

   _isAnimalLocked: function(animal) {
      var highest_level = this.get('highest_level');
      if (!highest_level) {
         highest_level = 0;
      }
      return animal.level_requirement > highest_level;
   },

   _updateLockedAnimals: function() {
      var animals = this.get('pastureTypes');
      if (animals) {
         radiant.sortByOrdinal(animals);
         for (var animal_id = 0; animal_id < animals.length; animal_id++) {
            var animal = animals[animal_id];
            var is_locked = this._isAnimalLocked(animal);
            Ember.set(animal, 'is_locked', is_locked);
         }
      }
   },

   _tracedMaxShepherdLevel: function () {
      Ember.run.scheduleOnce('afterRender', this, '_updateLockedAnimals')
   }.observes('highest_level')
});
