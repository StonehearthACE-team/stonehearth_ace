App.StonehearthZonesModeView.reopen({
   _examineEntity: function(entity) {
      if (!entity && this._propertyView) {
         this._propertyView.destroyWithoutDeselect();
         self._propertyView = null;
         return;
      }

      var viewType = null;
       if (entity['stonehearth:player_market_stall']) {
         viewType = App.StonehearthPlayerMarketStallView;
      } else if (entity['stonehearth:storage'] && entity['stonehearth:storage'].is_public) {
         // TODO: sigh, the above is probably wrong, but highly convenient.
         viewType = App.StonehearthStockpileView;
      } else if (entity['stonehearth:farmer_field']) {
         viewType = App.StonehearthFarmView;
      } else if (entity['stonehearth:trapping_grounds']) {
         viewType = App.StonehearthTrappingGroundsView;
      } else if (entity['stonehearth:mining_zone']) {
         viewType = App.StonehearthMiningZoneView;
      } else if (entity['stonehearth:shepherd_pasture']) {
         viewType = App.StonehearthPastureView;
      } else if (entity['stonehearth_ace:grower_underfield']) {
         viewType = App.StonehearthAceUnderfarmView;
      }
      if (viewType) {
         this._showZoneUi(entity, viewType);
      } else {
         if (this._propertyView) {
            this._propertyView.destroyWithoutDeselect();
            self._propertyView = null;
         }
      }
   }
});
