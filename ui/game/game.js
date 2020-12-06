App.StonehearthGameUiView.reopen({
   didInsertElement: function () {
      var self = this;

      $.getJSON('/stonehearth_ace/ui/data/game_hotkeys.json', function(data) {
         var hotkeys = [];
         radiant.each(data, function(k, v) {
            if (v) {
               v.key = k;
               hotkeys.push(v);
            }
         });

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
      });
   },
});
