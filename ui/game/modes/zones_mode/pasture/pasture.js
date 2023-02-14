App.StonehearthPastureView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'stonehearthPasture',
   closeOnEsc: true,
   _currentPastureType: '',

   components: {
      "uri": {},
      "stonehearth:unit_info": {},
      "stonehearth:shepherd_pasture" : {}
   },

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
      this._super();
      var self = this;

      this.$('button.ok').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:submenu_select'} );
         self.destroy();
      });

      this.$('button.warn').click(function() {
         radiant.call('stonehearth:destroy_entity', self.uri)
         self.destroy();
      });

      this.$('#disableButton').click(function() {
         //xxx toggle zone enabled and disabled state.
      });

      self._updateTooltip();

      // ACE: clicking checkboxes
      self.$('#harvestAnimalsCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_pasture_harvest_animals_renewable', self.get('uri'), this.checked);
      });
      self.$('#harvestGrassCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_pasture_harvest_grass', self.get('uri'), this.checked);
      });
      self.$('#collectStraysCheckbox').change(function() {
         radiant.call('stonehearth_ace:set_pasture_collect_strays', self.get('uri'), this.checked);
      });

      // ACE tooltips
      App.guiHelper.addTooltip(self.$('#maintainAnimalsLabel'), 'stonehearth_ace:ui.game.zones_mode.pasture.maintain_animals_description');
      App.guiHelper.addTooltip(self.$('#harvestAnimals'), 'stonehearth_ace:ui.game.zones_mode.pasture.harvest_animals_renewable_description');
      App.guiHelper.addTooltip(self.$('#harvestGrass'), 'stonehearth_ace:ui.game.zones_mode.pasture.harvest_grass_description');
      App.guiHelper.addTooltip(self.$('#collectStrays'), 'stonehearth_ace:ui.game.zones_mode.pasture.collect_strays_description');
   },

   willDestroyElement: function() {
      var self = this;
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('button.ok').off('click');
      this.$('button.warn').off('click');
      this.$('#disableButton').off('click');

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

   _pastureAnimalTypeChange: function() {
      var self = this;
      var currentPastureType = self.get('model.stonehearth:shepherd_pasture.pasture_type');

      self._currentPastureType = currentPastureType;
      if (!currentPastureType) {
         self._showPastureTypePalette();
         return;
      }

      var pastureData = self.get('model.uri.components.stonehearth:shepherd_pasture.pasture_data');
      var currentPastureData = pastureData[currentPastureType];
      if (currentPastureData) {
         self.set('currentPastureData', currentPastureData);
      }

      var capacityData = self.get('model.stonehearth:shepherd_pasture.max_population_data')
      var capacity = capacityData[currentPastureType];
      if (capacity) {
         self.set('capacity', capacity);
      }

      // ACE: check if the current animal type has a renewable resource component to it and set 'renewable' accordingly

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
         var pastureData = self.get('model.uri.components.stonehearth:shepherd_pasture.pasture_data');
         var pastureType = self.get('model.stonehearth:shepherd_pasture.pasture_type');
         if (pastureData && pastureType) {
            var min = pastureData[pastureType] && pastureData[pastureType].min_population || 2;
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
      }
   }.observes('model.stonehearth:shepherd_pasture.pasture_type'),

   _updateTooltip: function() {
      var pastureData = this.get('currentPastureData');
      if (pastureData && this.$('#pastureTypeImage')) {
         this.$('#pastureTypeImage').tooltipster({
            content: $('<div class=detailedTooltip><h2>' + i18n.t(pastureData.name) + '</h2>'
                        + i18n.t(pastureData.description) + '</div>')
         });
      }
   }.observes('currentPastureData'),

   _showPastureTypePalette: function() {
      if (!this.palette) {
         var pastureComponent = this.get('model.stonehearth:shepherd_pasture');
         this.palette = App.gameView.addView(App.StonehearthPastureTypePaletteView, {
            pasture: pastureComponent && pastureComponent.__self,
            pasture_view: this,
            pasture_data: this.get('model.uri.components.stonehearth:shepherd_pasture.pasture_data'),
         });
      }
   },

   // ACE: handle updates to extra pasture settings
   _pastureChanged: function() {
      var self = this;
      var harvestAnimals = self.get('model.stonehearth:shepherd_pasture.harvest_animals_renewable');
      var harvestGrass = self.get('model.stonehearth:shepherd_pasture.harvest_grass');
      var collectStrays = self.get('model.stonehearth:shepherd_pasture.collect_strays') === false ? false : true;

      self.$('#harvestAnimalsCheckbox').prop('checked', harvestAnimals);
      self.$('#harvestGrassCheckbox').prop('checked', harvestGrass);
      self.$('#collectStraysCheckbox').prop('checked', collectStrays);
   }.observes('model.stonehearth:shepherd_pasture'),

   _tracedShepherdJobInfo: function() {
      if (this.palette) {
         this.palette.set('highest_level', this.get('shepherd_job_info.highest_level'));
      }
   }.observes('shepherd_job_info.highest_level'),

   actions :  {
      choosePastureTypeLinkClicked: function() {
         this._showPastureTypePalette();
      },
   },
   destroy: function() {
      if (this.palette) {
         this.palette.destroy();
         this.palette = null;
      }
      this._super();
   },
});

App.StonehearthPastureTypePaletteView = App.View.extend({
   templateName: 'stonehearthPastureTypePalette',
   modal: true,

   didInsertElement: function() {
      this._super();
      var self = this;

      var pastureDataArray = [];
      radiant.each(self.pasture_data, function(key, data) {
         var pastureData = {
            type: key,
            icon: data.icon,
            name: data.name,
            description: data.description
         }
         pastureDataArray.push(pastureData);
      });
      self.set('pastureTypes', pastureDataArray);

      // ACE: better handling of locked pasture types and sorting
      this.$().on( 'click', '[pastureType]', function() {
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

   willDestroyElement: function() {
      this.$().off('click', '[pastureType]');
      this._super();
   },

   destroy: function() {
      if (this.pasture_view) {
         this.pasture_view.palette = null;
      }
      this._super();
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
