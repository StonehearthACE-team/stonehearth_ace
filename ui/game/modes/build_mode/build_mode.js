App.StonehearthBuildModeView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      // track game mode changes and nuke any UI that we've show when we exit build mode
      var prevMode;
      $(top).off('mode_changed').on('mode_changed', function(_, mode) {
         if (prevMode == 'build' || mode == 'build') {
            self._onStateChanged();
         }
         prevMode = mode;
      });
   }
});
