App.StonehearthStockpileView.reopen({
   destroy: function() {
      if (self._townTrace) {
         self._townTrace.destroy();
         self._townTrace = null;
      }
      this._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      radiant.call('stonehearth:get_town')
         .done(function (response) {
            self._townTrace = new StonehearthDataTrace(response.result, {})
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }

                  self._defaultStorageItems = response.default_storage;
                  self._updateDefaultStorage();
               });
         });

      App.tooltipHelper.attachTooltipster(self.$('#defaultStorageLabel'),
         $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.default_storage.tooltip')))
      );

      var defaultStorage = self.$('#defaultStorage');
      defaultStorage.click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:action_click'} );
         radiant.call('stonehearth_ace:set_default_storage', self.uri, defaultStorage.prop('checked'));
      });
   },

   _updateDefaultStorage: function() {
      var self = this;
      var isDefault = false;
      var defaultStorage = self.$('#defaultStorage');

      if (self._defaultStorageItems) {
         radiant.each(self._defaultStorageItems, function(id, storage) {
            if (storage == self.uri) {
               isDefault = true;
               defaultStorage.prop('checked', true);
            }
         });
      }

      if (!isDefault) {
         defaultStorage.prop('checked', false);
      }
   }.observes('model.uri'),

   _isSingleFilter: function() {
      return this.get('model.stonehearth:storage.is_single_filter');
   }.property('isSingleFilter')
});
