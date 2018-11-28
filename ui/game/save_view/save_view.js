App.SaveView.reopen({
   _saveGame: function(saveid, saveName, onDone, onFail, onAlways) {
      var self = this;
      var d = new Date();
      var gameDate = App.gameView.getDateTime();

      if (!saveid) {
         // Generate a new saveid
         saveid = String(d.getTime());
      }

      var name;
      if (saveid == 'auto_save') {
         name = i18n.t('stonehearth:ui.game.save_view.auto_save_prefix');
      } else if (saveName) {
         name = saveName;
      } else {
         name = '';
      }

      radiant.call("stonehearth_ace:save_game_command")
         .done(function() {
            radiant.call("radiant:client:save_game", saveid, {
               name: name,
               town_name: App.stonehearthClient.settlementName(),
               game_date: gameDate,
               timestamp: d.getTime(),
               time: d.toLocaleString(),
               jobs: {
                  crafters: App.jobController.getNumCrafters(),
                  workers: App.jobController.getNumWorkers(),
                  soldiers: App.jobController.getNumSoldiers(),
               }
            })
            .done(function() { if(onDone) onDone(); })
            .fail(function() { if(onFail) onFail(); })
            .always(function() { if(onAlways) onAlways(); });
         })
         .fail(function() { if(onFail) onFail(); })
         .always(function() { if(onAlways) onAlways(); });
   },

   _overwriteSaveGame: function(saveid, saveName) {
      var self = this;

      self._showSaveModal();
      self._saveGame(null, saveName,
            function() {
               radiant.call("radiant:client:delete_save_game", saveid)
                  .always(function() {
                     self._hideSaveModal();
                     self.refreshSavesList(true);
                  })
            },
            function() {
               self._hideSaveModal();
               self.refreshSavesList();
            });
   },

   actions: {
      saveGame: function(saveid) {
         if (this.$('#deleteSaveButton').hasClass('disabled')) {
            return;
         }

         var self = this;

         self._showSaveModal();
         self._saveGame(saveid, null, null, null,
               function() {
                  self._hideSaveModal();
                  self.refreshSavesList(true);
               });
      }
   }
});