App.StonehearthTradeMenuView.reopen({
   buildSourceSellable: function() {
      var self = this;
      self._super();
      self._sourceSellablePalette.stonehearthItemPalette('showSearchFilter');
   },

   buildTargetSellable: function() {
      var self = this;
      self._super();
      self._targetSellablePalette.stonehearthItemPalette('showSearchFilter');
   },
});
