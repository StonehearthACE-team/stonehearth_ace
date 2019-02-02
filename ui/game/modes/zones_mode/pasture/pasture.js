App.StonehearthPastureView.reopen({
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
         var vals = [];
         for (var i = capacity; i >= 0; i--) {
            vals.push(i + '');
         }

         var onChanged = function (key, value) {
            var val = parseInt(value);
            if (val != NaN) {
               radiant.call('stonehearth_ace:set_pasture_maintain_animals', self.get('uri'), val);
            }
         };

         selector = App.guiHelper.createCustomSelector('pasture_maintainAnimals', vals, onChanged);
         App.guiHelper.setListSelectorValue(selector, maintain + '');

         self._maintainSelector = selector;
         self.$('#maintainAnimals').append(selector);
      }
   }.observes('model.stonehearth:shepherd_pasture.pasture_type'),
});
