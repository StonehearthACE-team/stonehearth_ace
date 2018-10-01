App.StonehearthAceUnderfarmView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'stonehearthAceUnderfarm',
   closeOnEsc: true,

   components: {
      "stonehearth:unit_info": {},
      "stonehearth_ace:grower_underfield" : {
         "current_undercrop_alias": {}
      }
   },

   init: function() {
      this._super();

      var self = this;

      radiant.call_obj('stonehearth.job', 'get_job_call', 'stonehearth:jobs:farmer')
               .done(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  if (response.job_info_object) {
                     self.set('grower_job_info', response.job_info_object);
                  }
               });
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self.$('button.warn').click(function() {
         radiant.call('stonehearth:destroy_entity', self.uri)
         self.destroy();
      });

      self.$('button.ok').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:submenu_select'} );
         self.destroy();
      });

      self.hasShownPaletteOnce = false;
   },

   willDestroyElement: function() {

      self.$('button.warn').off('click');
      self.$('button.ok').off('click');

      this._super();
   },

   destroy: function() {
      if (this.palette) {
         this.palette.destroy();
         this.palette = null;
      }
      this._super();
   },

   _onFieldChanged: function() {
      var field = this.get('model.stonehearth_ace:grower_underfield');
      if (field && field.has_set_undercrop || this.hasShownPaletteOnce) {
         return;
      }
      this._createPalette();
   }.observes('model.stonehearth_ace:grower_underfield.has_set_undercrop'),

   _tracedFieldChanged: function() {
      this.hasShownPaletteOnce = false;
   }.observes('uri'),

   _tracedFarmerJobInfo: function() {
      if (this.palette) {
         this.palette.set('uri', this.get('grower_job_info'));
      }
   }.observes('grower_job_info'),

   _createPalette: function() {
      if (!this.palette) {
         var self = this;
         if (!self.get('model.stonehearth_ace:grower_underfield')) return;
         self.palette = App.gameView.addView(App.StonehearthFarmCropPalette, {
                        field: self.get('model.stonehearth_ace:grower_underfield').__self,
                        farm_view: self,
                        uri: self.get('grower_job_info')
                     });
      }
   },

   actions :  {
      addCropButtonClicked: function() {
         this._createPalette();
      },
   },
});

App.StonehearthAceUnderfarmCropPalette = App.View.extend({
   templateName: 'stonehearthAceUndercropPalette',
   modal: true,
   uriProperty: 'model',
   components: {

   },

   init: function() {
      var self = this;
      this._super();
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );

      //Get the undercrops available for this farm
      radiant.call('stonehearth:get_all_undercrops')
         .done(function (o) {
            if (self.isDestroyed || self.isDestroying) return;
            self.set('undercrops', radiant.map_to_array(o.all_undercrops, function (k, v) {
               if (v.undercrop_info.preferred_seasons) {
                  v.undercrop_info.preferred_seasons = _.map(v.undercrop_info.preferred_seasons, i18n.t).join(', ');
               }
               return v;
            }));
            self._updateLockedCrops();
         });
   },

   _isCropLocked: function(undercrop) {
      var highest_level = this.get('model.highest_level');
      if (!highest_level) {
         highest_level = 0;
      }
      return undercrop.undercrop_level_requirement > highest_level;
   },

   _isCropHidden: function (undercrop) {
      if (!this.get('model') || !undercrop.undercrop_key) return false; // Too early. We'll recheck later.
      var manually_unlocked = this.get('model.manually_unlocked');
      return !undercrop.initial_undercrop && !manually_unlocked[undercrop.undercrop_key];
   },

   _updateLockedCrops: function() {
      var undercrops = this.get('undercrops');
      if (undercrops) {
         radiant.sortByOrdinal(undercrops);
         for (var undercrop_id = 0; undercrop_id < undercrops.length; undercrop_id++) {
            var undercrop = undercrops[undercrop_id];
            var is_locked = this._isCropLocked(undercrop);
            var is_hidden = this._isCropHidden(undercrop);
            Ember.set(undercrop, 'is_locked', is_locked);
            Ember.set(undercrop, 'is_hidden', is_hidden)
         }
      }
   },

   _tracedMaxFarmerLevel: function () {
      Ember.run.scheduleOnce('afterRender', this, '_updateLockedCrops')
   }.observes('model.highest_level', 'model.manually_unlocked'),

   _tooltipifyPreferredSeasons: function () {
      Ember.run.scheduleOnce('afterRender', this, function () {
         self.$('.preferredSeasons').tooltipster({
            content: i18n.t('stonehearth_ace:ui.game.zones_mode.underfarm.preferred_seasons_tooltip', {
               num: App.constants.underfarming.NONPREFERRED_SEASON_GROWTH_TIME_MULTIPLIER
            })
         });
      });
   }.observes('undercrops'),

   didInsertElement: function() {
      this._super();
      var self = this;

      this.$().on( 'click', '[undercrop]', function() {
         if ($(this).attr('locked')) {
            return;
         }
         var undercropId = $(this).attr('undercrop');
         if (undercropId) {
            radiant.call_obj(self.field, 'set_undercrop', undercropId);
            self.farm_view.hasShownPaletteOnce = true;
         }
         self.destroy();
      });
   },

   destroy: function() {
      if (this.farm_view) {
         this.farm_view.palette = null;
      }
      this._super();
   },

   willDestroyElement: function() {
      this.$().off('click', '[undercrop]');
      this._super();
   }
});
