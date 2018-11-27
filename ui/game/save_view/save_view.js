App.SaveView.reopen({
   _saveGame: function(saveid, saveName) {
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

      return radiant.call("stonehearth_ace:save_game_command", saveid, {
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
         });
}
});