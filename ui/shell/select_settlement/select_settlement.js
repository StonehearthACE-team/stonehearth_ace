App.StonehearthSelectSettlementView.reopen({
	
	_loadSeasons: function () {
      var self = this;
      var biome_uri = self.get('options.biome_src');
      if (biome_uri) {
         self.trace = radiant.trace(biome_uri)
            .progress(function (biome) {
               self.set('seasons', radiant.map_to_array(biome.seasons, function(k, b) { b.id = k; }));

               Ember.run.scheduleOnce('afterRender', this, function () {
                  var seasonDivs = self.$('[data-season-id]');
                  if (seasonDivs) {
                     seasonDivs.each(function () {
                        var $el = $(this);
                        var id = $el.attr('data-season-id');
                        var description = biome.seasons[id].description;
                        if (description) {
                           var tooltip = $(App.tooltipHelper.createTooltip(null, i18n.t(description, {escapeHTML: true})));
                           $el.tooltipster({ content: tooltip, position: 'bottom' });
                        }
                     });
                     if (biome.default_starting_season) {
                        self.$('[data-season-id="' + biome.default_starting_season + '"] input').attr('checked', true);
                     } else {
                        self.$('[data-season-id] input').first().attr('checked', true);
                     }
                  }
               });
            })
      }
   }.observes('options.biome_src')
});
