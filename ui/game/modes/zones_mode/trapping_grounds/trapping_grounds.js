App.StonehearthTrappingGroundsView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'stonehearthTrappingGrounds',
   closeOnEsc: true,

   components: {
      "uri": {},
      "stonehearth:unit_info": {},
      "stonehearth:trapping_grounds" : {}
   },

   init: function() {
      this._super();
      var self = this;

      radiant.call_obj('stonehearth.trapping', 'get_all_trappable_animals_command')
         .done(function (response) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }

            self.set('allTrappableAnimals', response.animals);
         });

      radiant.call_obj('stonehearth.job', 'get_job_call', 'stonehearth:jobs:trapper')
         .done(function(response) {
            if (response.job_info_object) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }

               self.set('trapperJobInfo', response.job_info_object);
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
      
      // ACE: add wilderness level
      self._trappingGroundsWildernessLevelChange();
   },

   willDestroyElement: function() {
      this.$('button.ok').off('click');
      this.$('button.warn').off('click');
      this.$('#disableButton').off('click');

      this._super();
   },

   _trappingGroundsTypeChange: function() {
      var self = this;
      var currentTrappingGroundsType = self.get('model.stonehearth:trapping_grounds.trapping_grounds_type');

      self._currentTrappingGroundsType = currentTrappingGroundsType;
      if (!currentTrappingGroundsType) {
         self._showTrappingGroundsTypePalette();
         return;
      }

      var trappingGroundsData = self.get('allTrappableAnimals');
      if (trappingGroundsData) {
         var currentTrappingGroundsData = trappingGroundsData[currentTrappingGroundsType];
         if (currentTrappingGroundsData) {
            self.set('currentTrappingGroundsData', currentTrappingGroundsData);
         }
      }
   }.observes('model.stonehearth:trapping_grounds.trapping_grounds_type', 'allTrappableAnimals'),

   // ACE: handle wilderness level
   _trappingGroundsWildernessLevelChange: function() {
      var self = this;
      var currentWildernessLevel = self.get('model.stonehearth:trapping_grounds.wilderness_level');
      
      if (currentWildernessLevel) {
         var color = currentWildernessLevel.heatmap_color;
         // use the heatmap color, except use a standard (reduced) alpha
         self.set('wildernessBackgroundColorStyle', `background-color: rgba(${color[0]},${color[1]},${color[2]},0.75)`)
      }
      else {
         self.set('wildernessBackgroundColorStyle', '')
      }
      self.set('currentWildernessLevel', currentWildernessLevel);
   }.observes('model.stonehearth:trapping_grounds.wilderness_level'),

   // ACE: destroy old tooltip and update with latest info
   _updateTooltip: function() {
      var trappingGroundsData = this.get('currentTrappingGroundsData');
      var trappingGroundsTypeImage = this.$('#trappingGroundsTypeImage');
      if (trappingGroundsData && trappingGroundsTypeImage) {
         if (trappingGroundsTypeImage.hasClass('tooltipstered')) {
            trappingGroundsTypeImage.tooltipster('destroy');
         }
         trappingGroundsTypeImage.tooltipster({
            content: $('<div class=detailedTooltip><h2>' + i18n.t(trappingGroundsData.name) + '</h2>'
                        + i18n.t(trappingGroundsData.description) + '</div>')
         });
      }
   }.observes('currentTrappingGroundsData'),

   _tracedFarmerJobInfo: function() {
      if (this.palette) {
         this.palette.set('uri', this.get('trapperJobInfo'));
      }
   }.observes('trapperJobInfo'),

   _showTrappingGroundsTypePalette: function() {
      if (!this.palette && this.get('model.stonehearth:trapping_grounds')) {
         this.palette = App.gameView.addView(App.StonehearthTrappingGroundsTypePaletteView, {
            trapping_grounds: this.get('model.stonehearth:trapping_grounds').__self,
            trapping_grounds_view: this,
            uri: this.get('trapperJobInfo')
         });
      }
   },

   actions :  {
      chooseTrappingGroundsTypeLinkClicked: function() {
         this._showTrappingGroundsTypePalette();
      },
   },
   destroy: function() {
      if (this.palette) {
         this.palette.destroy();
         this.palette = null;
      }
      this._super();
   }
});

App.StonehearthTrappingGroundsTypePaletteView = App.View.extend({
   templateName: 'stonehearthTrappingGroundsTypePalette',
   modal: true,
   uriProperty: 'model',
   components: {},

   didInsertElement: function() {
      this._super();
      var self = this;

      radiant.call_obj('stonehearth.trapping', 'get_all_trappable_animals_command')
         .done(function (response) {
            if (self.isDestroyed || self.isDestroying) return;
            self._trappableAnimals = response.animals;
            self._updatePalette();
         });

      this.$().on( 'click', '[trappingGroundsType]', function() {
         if ($(this).attr('locked')) {
            return;
         }

         var trappingGroundsType = $(this).attr('trappingGroundsType');
         if (trappingGroundsType) {
            radiant.call_obj(self.trapping_grounds, 'set_trapping_grounds_type_command', trappingGroundsType);
         }
         self.destroy();
      });
   },

   _updatePalette: function() {
      var self = this;
      var trappingGroundsDataArray = [];
      radiant.each(self._trappableAnimals, function(key, data) {
         var trappingGroundsData = {
            type: key,
            icon: data.icon,
            name: data.name,
            description: data.description,
            level_requirement: data.level_requirement,
            ordinal: data.ordinal,
            is_locked: self._isLocked(data)
         }
         trappingGroundsDataArray.push(trappingGroundsData);
      });

      radiant.sortByOrdinal(trappingGroundsDataArray);

      self.set('trappingGroundsTypes', trappingGroundsDataArray);
   }.observes('model.highest_level'),

   _isLocked: function(data) {
      var highest_level = this.get('model.highest_level');
      if (!highest_level) {
         highest_level = 0;
      }

      return highest_level < data.level_requirement;
   },

   willDestroyElement: function() {
      this.$().off('click', '[trappingGroundsType]');
      this._super();
   },

   destroy: function() {
      if (this.trapping_grounds_view) {
         this.trapping_grounds_view.palette = null;
      }
      this._super();
   }
});
