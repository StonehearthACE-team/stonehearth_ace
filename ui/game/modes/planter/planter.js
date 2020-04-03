App.AceHerbalistPlanterView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'acePlanter',
   closeOnEsc: true,
   _currentCropType: null,

   components: {
      "stonehearth:storage" : {},
      "stonehearth_ace:herbalist_planter" : {}
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
            self.set('allCropData', response.data);
         });
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self.$('#enableHarvestCheckbox').change(function() {
         var planter = self.get('model.stonehearth_ace:herbalist_planter');
         radiant.call_obj(planter && planter.__self, 'set_harvest_enabled_command', this.checked);
      })

      // tooltips
      App.guiHelper.addTooltip(self.$('#enableHarvest'), 'stonehearth_ace:ui.game.herbalist_planter.harvest_crop_description');

      self._updateTooltip();
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');

      this._super();
   },

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
            allowed_crops: planterComponent.allowed_crops
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

      var no_crop = self.planter_data.no_crop;
      cropDataArray.push({
         type: 'no_crop',
         icon: no_crop.icon,
         level: -1,
         display_name: no_crop.display_name,
         description: no_crop.description
      });

      var allowed_crops = self.allowed_crops || self.planter_data.default_allowed_crops;
      radiant.each(self.planter_data.crops, function(key, data) {
         if (allowed_crops[key]) {
            var planterData = {
               type: key,
               icon: data.icon,
               level: Math.max(0, data.level || 0),
               display_name: i18n.t(data.display_name),
               description: i18n.t(data.description)
            }
            cropDataArray.push(planterData);
         }
      });
      
      cropDataArray.sort((a, b) => {
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
      });
      self.set('cropTypes', cropDataArray);

      this.$().on( 'click', '[cropType]', function() {
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
