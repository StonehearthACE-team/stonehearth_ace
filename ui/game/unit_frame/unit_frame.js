$(top).on('stonehearthReady', function (cc) {
   if (!App.gameView) {
      return;
   }
   var unitFrameExtras = App.gameView.getView(App.UnitFrameExtrasView);
   if (!unitFrameExtras) {
      App.gameView.addView(App.UnitFrameExtrasView, {});
   }
});

App.UnitFrameExtrasView = App.View.extend({
   templateName: 'unitFrameExtras'
});

App.StonehearthUnitFrameView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      var btn = self.$('#unitFrameExtras');
      if (btn.length < 1) {
         var div = $("#unitFrameExtras");
         div.appendTo(self.$("#unitFrame"));
         btn = self.$('#componentInfoButton');
         btn.on('click', self.toggleComponentInfo);
      }

      $(top).on("selection_has_component_info_changed", function (_, e) {
         if (e.has_component_info) {
            self.$('#componentInfoButton').show();
         }
         else {
            self.$('#componentInfoButton').hide();
         }
      });
   },

   toggleComponentInfo: function() {
      $(top).trigger('component_info_toggled', {});
   },

   showPromotionTree: function() {
      var entity = App.stonehearthClient.getSelectedEntity()
      if (entity) {
         App.stonehearthClient.showPromotionTree(entity);
      }
   }
});
