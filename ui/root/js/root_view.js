// other modders can also reopen this, override init, and add their own custom modes and entity mode checks
App.RootView.reopen({
   init: function() {
      this._super();
      var self = this;

      self._game_mode_manager.addCustomMode("military", "hud", "fight_menu", "AceMilitaryModeView", true);
      self._game_mode_manager.addCustomMode("connection", "hud");
      self._game_mode_manager.addCustomEntityModeCheck(self._ACE_getCustomModeForEntity);
   },

   _ACE_getCustomModeForEntity: function(modes, entity) {
      if (entity['stonehearth_ace:patrol_banner']) {
         return modes.MILITARY;
      }

      if (entity['stonehearth_ace:connection']) {
         return modes.CONNECTION;
      }

      return null;
   }
});