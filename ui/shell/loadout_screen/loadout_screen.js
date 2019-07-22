App.StonehearthLoadoutScreenView.reopen({
   willDestroyElement: function() {
      var self = this;
      self.$().off('click');
      self.$().find('.tooltipstered').tooltipster('destroy');
   },

   // for some reason, the loadout item icons are "underneath" the main row divs, so they don't get hovered
   // also, just name and description isn't very useful, so don't bother with tooltips unless we increase their utility
   
   // _selectLoadout: function(id) {
   //    var self = this;
   //    //self._super(id);

   //    Ember.run.scheduleOnce('afterRender', this, function() {
   //       self.$('.loadoutContentColumn').each((i, el) => {
   //          var div = $(el);
   //          var uri = div.attr('data-uri');
   //          var catalogData = App.catalog.getCatalogData(uri);
   //          if (catalogData) {
   //             var tooltipString = App.tooltipHelper.createTooltip(i18n.t(catalogData.display_name), i18n.t(catalogData.description));
   //             App.tooltipHelper.attachTooltipster(div, $(tooltipString));
   //          }
   //       });
   //    });
   //    self.set('selected', self._loadouts[id]);
   //    $('[loadout_id="' + id + '"]').children('.loadoutRowBorder').addClass('selectedLoadout');
   // }
});
