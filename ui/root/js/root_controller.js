App.RootController.reopen({
   _minAutoSaveInterval: 5,   // minutes
   _maxAutoSaveInterval: 30,   // minutes
   
   init: function() {
      var self = this;
      self._super();

      self._autoSaveInterval = self._minAutoSaveInterval * 60 * 1000

      stonehearth_ace.getModConfigSetting('stonehearth_ace', 'auto_save_interval', function(value) {
            self._setAutoSaveInterval(value);
         });
      $(top).on("auto_save_interval_changed", function (_, e) {
         self._setAutoSaveInterval(e.value);
      });
   },

   _setAutoSaveInterval: function(interval) {
      var self = this;
      self._autoSaveInterval = Math.max(self._minAutoSaveInterval, Math.min(self._maxAutoSaveInterval, parseInt(interval || 0))) * 60 * 1000;
   },

   // have to override this to defer resume
   // _autoSave: function() {
   //    var self = this;
   //    var saveView = App.stonehearthClient.getSaveView();
   //    var enabled = saveView.get('auto_save');
   //    var escMenuView = App.gameView ? App.gameView.getView(App.StonehearthEscMenuView) : null;
   //    var escMenuVisible = escMenuView ? (!escMenuView.isDestroyed && !escMenuView.isDestroying) : false;

   //    if (enabled && !escMenuVisible) {
   //       radiant.call('stonehearth:dm_pause_game')
   //          .done(function(response) {
   //             saveView.send('saveGame', 'auto_save', function() {
   //                radiant.call('stonehearth:dm_resume_game');
   //             });
   //          });
   //    }
   // },

   actions: {
      // every X minutes, check if autosave is enabled, and if it is, save.
      // override this function completely to use timeouts instead of intervals to easily transition auto save intervals
      tryAutoSave: function(start) {
         var self = this;
          // Get the controller once to initialize it (Sigh)
          // Otherwise we don't get the controller when we first try to save -yshan
         var saveView = App.stonehearthClient.getSaveView();
         if (start) {
            this._timeoutTicket = setTimeout(function autoSaveTimeout() {
                  //only autosave if we're the host
                  if (App.stonehearthClient.isHostPlayer()) {
                     self._autoSave();
                     self._timeoutTicket = setTimeout(autoSaveTimeout, self._autoSaveInterval);
                  }
               }, self._autoSaveInterval);
         } else {
            clearTimeout(this._timeoutTicket);
         }
      },
   },
})
