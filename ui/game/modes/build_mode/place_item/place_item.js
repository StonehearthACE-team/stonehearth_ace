App.StonehearthPlaceItemPaletteView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      if (self._palette) {
         self._palette.stonehearthItemPalette('showSearchFilter');
      }
   },
});
