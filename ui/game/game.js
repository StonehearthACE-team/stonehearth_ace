App.StonehearthGameUiView.reopen({
   didInsertElement: function () {
      var self = this;

      var hotkeys = stonehearth_ace.getUIHotkeys().game;
      hotkeys.forEach(keyData => {
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
});
