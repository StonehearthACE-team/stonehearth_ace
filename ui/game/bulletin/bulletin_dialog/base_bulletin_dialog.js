App.StonehearthBaseBulletinDialog.reopen({
	didInsertElement: function() {
      var self = this;
      self._super();
      self.createDynamicTooltips();
   },

   willDestroyElement: function() {
      var self = this;
      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.questItemsCached');
      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.numCached');
      self._super();
   },

   createDynamicTooltips: function() {
      var self = this;

      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.questItemsCached');
      App.guiHelper.removeDynamicTooltip(self.$('.window'), '.numCached');

      App.guiHelper.createDynamicTooltip(self.$('.window'), '.questItemsCached', function() {
         if (self.$('.window .questItemsCached').hasClass('fullyCached')) {
            return $(App.tooltipHelper.createTooltip(null, i18n.t(`stonehearth_ace:ui.game.bulletin.generic.fully_cached`)));
         }
      });
      App.guiHelper.createDynamicTooltip(self.$('.window'), '.numCached', function() {
         return $(App.tooltipHelper.createTooltip(null, i18n.t(`stonehearth_ace:ui.game.bulletin.generic.num_cached`)));
      });
   },
});
