var gameHotkeys = [];
$.getJSON('/stonehearth_ace/ui/data/game_hotkeys.json', function(data) {
   var hotkeys = [];
   radiant.each(data, function(k, v) {
      if (v) {
         v.key = k;
         hotkeys.push(v);
      }
   });

   gameHotkeys = hotkeys;
});

App.StonehearthGameUiView.reopen({
   didInsertElement: function () {
      var self = this;

      gameHotkeys.forEach(keyData => {
         var key = keyData.key;
         var btn = $(`<button style="display: none" hotkey_action="${key}">${key}</button>`);
         self.$().append(btn);
         btn.click(function(e) {
            if (keyData.event) {
               $(top).trigger(keyData.event, keyData.eventArgs)
            }
         });
      });

      self._super();
   },

   addCompleteViews: function() {
      this._addViews(this.views.complete);

      // Preconstruct these views as well
      // Wait until a delay period after start menu load
      // so that we can offset some of the load time until later
      App.waitForStartMenuLoad().then(() => {
         setTimeout(() => {
            App.stonehearthClient.showSettings(true); // true for hide
            App.stonehearthClient.showSaveMenu(true);
            App.stonehearthClient.showCitizenManager(true);
            App.stonehearthClient.showMercantileView(true);
            App.stonehearthClient.showMultiplayerMenu(true);
         }, 500);
      });
   },
});
