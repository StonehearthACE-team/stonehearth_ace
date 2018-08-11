App.StonehearthTerrainVisionWidget.reopen({
   init: function() {
      var self = this;

      self._super();

      radiant.call('stonehearth_ace:get_client_service', 'heatmap').done(function (r) {
         self._appealHeatmapServiceAddress = r.result;
      });
   },

   setAppealHeatmapActive: function (isActive) {
      var self = this;
      self.set('appeal_heatmap_active', isActive);
      if (self._appealProbeTrace) {
         self._appealProbeTrace.destroy();
      }
      if (isActive) {
         radiant.call_obj('stonehearth_ace.heatmap', 'show_heatmap_command', 'appeal');
         self._currentTip = App.stonehearthClient.showTip('stonehearth:ui.game.visions.appeal_vision',
                                                          'stonehearth:ui.game.visions.appeal_vision_description',
                                                          { i18n: true });
         self._appealProbeTrace = new RadiantTrace();
         self._appealProbeTrace.traceUri(self._appealHeatmapServiceAddress, {}).progress(function (response) {
            var appeal = response.current_probe_value;
            self.set('currentAppeal', response.current_probe_value);
            var thresholds = radiant.deep_copy_pod(App.constants.appeal.LEVELS);
            for (var i = 0; i < thresholds.length; ++i) {
               var threshold = thresholds[i];
               if (appeal < threshold.max) {
                  self.set('currentAppealIcon', '/stonehearth/data/horde/' + threshold.icon);
                  self.set('currentAppealLabel', i18n.t(threshold.ui_label).replace(/\s+/g, '<br/>'));
                  break;
               }
            };
         });
         $(document).bind('mousemove.appealCursorReadout', function (e) {
            var readout = $('#appealCursorReadout');
            readout.css({ left: e.pageX - readout.width() / 2 + 16, top: e.pageY });
            var handle = $('#appealCursorReadout .handle');
            handle.css({ left: readout.width() / 2 - handle.width() / 2 });
         });
      } else {
         App.stonehearthClient.hideTip(self._currentTip);
         self.set('currentAppeal', null);
         self.set('currentAppealIcon', null);
         self.set('currentAppealLabel', null);
         radiant.call_obj('stonehearth_ace.heatmap', 'hide_heatmap_command');
         $(document).unbind('mousemove.appealCursorReadout');
      }
   }
});
