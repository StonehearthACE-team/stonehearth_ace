App.StonehearthTerrainVisionWidget.reopen({
    // source: https://stackoverflow.com/questions/8051975/access-object-child-properties-using-a-dot-notation-string
    // is there a radiant version of this somewhere?
    getDescendantProp: function (obj, desc) {
        var arr = desc.split('.');
        while (arr.length && (obj = obj[arr.shift()]));
        return obj;
    },

    init: function() {
      var self = this;

      self._super();

      radiant.call('stonehearth_ace:get_client_service', 'heatmap').done(function (r) {
         self._heatmapServiceAddress = r.result;
         radiant.call_obj('stonehearth_ace.heatmap', 'get_heatmaps_command').done(function (response) {
            var heatmaps = response.heatmaps;
            radiant.each(heatmaps, function(key, heatmap) {
                heatmap.key = key;
                heatmap.description = i18n.t(heatmap.description);
            });
            self._heatmaps = heatmaps;
            
            var heatmapArray = radiant.map_to_array(heatmaps)
            radiant.sortByOrdinal(heatmapArray);
            self.set('heatMaps', heatmapArray);
         });
      });
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      //self.$('#heatmapButton').tooltipster();

      // when the user clicks the heatmap menu button, hide the current heatmap and the menu
      self.$('#heatmapButton').on('click', function() {
         self.setHeatmapActive();
      });
      // when the user clicks a heatmap button, show that heatmap and hide the menu
      var heatmapList = self.$('#heatmapList');
      heatmapList.on('click', '.heatmap', function() {
         event.stopPropagation();
         var key = $(this).attr('data-key');
         self.setHeatmapActive(key, true);
         heatmapList.hide();
         heatmapList.attr('style', '');
      });
   },

   willDestroyElement: function() {
      var self = this;
      self._super();

      //self.$().find('.tooltipstered').tooltipster('destroy');
   },

   setHeatmapActive: function (heatmapKey, isActive) {
      var self = this;
      // if heatmapKey is null, we're making it inactive
      isActive = isActive && (heatmapKey != null);
      self.set('heatmap_active', isActive);
      if (self._heatmapValueTrace) {
         self._heatmapValueTrace.destroy();
      }
      var heatmapData = self._heatmaps && self._heatmaps[heatmapKey];
      if (isActive && heatmapData) {
         radiant.call_obj('stonehearth_ace.heatmap', 'show_heatmap_command', heatmapKey)
            .done(function(response) {
               if(heatmapKey != null && response.hidden) {
                  self.setHeatmapActive(heatmapKey, false);
               }
            });
         self._currentTip = App.stonehearthClient.showTip(heatmapData.name, heatmapData.description, { i18n: true });
         self._heatmapValueTrace = new RadiantTrace();
         self._heatmapValueTrace.traceUri(self._heatmapServiceAddress, {}).progress(function (response) {
            var heat_value = response.current_probe_value;
            self.set('currentHeatValue', response.current_probe_value);
            if (heatmapData.constants_key) {
                var thresholds = radiant.deep_copy_pod(self.getDescendantProp(App.constants, heatmapData.constants_key + '.LEVELS'));
                for (var i = 0; i < thresholds.length; ++i) {
                    var threshold = thresholds[i];
                    if (heat_value < threshold.max) {
                        var icon_path = threshold.icon
                        if (icon_path[0] != '/') {
                            icon_path = '/stonehearth/data/horde/' + icon_path;
                        }
                        self.set('currentHeatValueIcon', icon_path);
                        self.set('currentHeatValueLabel', i18n.t(threshold.ui_label).replace(/\s+/g, '<br/>'));
                        break;
                    }
                };
            }
            else {
                self.set('currentHeatValueIcon', heatmapData.icon);
                self.set('currentHeatValueLabel', i18n.t(heatmapData.description).replace(/\s+/g, '<br/>'));
            }
         });
         $(document).bind('mousemove.heatmapCursorReadout', function (e) {
            var readout = $('#heatmapCursorReadout');
            readout.css({ left: e.pageX - readout.width() / 2 + 16, top: e.pageY });
            var handle = $('#heatmapCursorReadout .handle');
            handle.css({ left: readout.width() / 2 - handle.width() / 2 });
         });
      } else {
         App.stonehearthClient.hideTip(self._currentTip);
         self.set('currentHeatValue', null);
         self.set('currentHeatValueIcon', null);
         self.set('currentHeatValueLabel', null);
         radiant.call_obj('stonehearth_ace.heatmap', 'hide_heatmap_command');
         $(document).unbind('mousemove.heatmapCursorReadout');
      }
   }
});
