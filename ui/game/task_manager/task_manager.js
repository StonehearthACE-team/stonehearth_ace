App.StonehearthTaskManagerView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      $(top).on('show_processing_meter_changed', function (_, e) {
         if (e.value) {
            // simply show the meter in the taskbar
            $('#taskManager').find('#meter').show();
         }
         else {
            // if we're hiding it, we need to make sure the details part is also hidden
            $('#taskManager').find('#details').hide();
            $('#taskManager').find('#meter').hide();
         }
      });

      // need to apply the setting on load as well
      radiant.call('radiant:get_config', 'mods.stonehearth_ace.show_processing_meter')
      .done(function(o) {
         var show_processing_meter = o['mods.stonehearth_ace.show_processing_meter'] || false;
         var e = {
            value: show_processing_meter
         };
         $(top).trigger('show_processing_meter_changed', e);
      });
   }
});