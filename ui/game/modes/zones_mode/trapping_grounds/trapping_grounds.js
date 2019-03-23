App.StonehearthTrappingGroundsView.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      self._trappingGroundsWildernessLevelChange();
   },

   _trappingGroundsWildernessLevelChange: function() {
      var self = this;
      var currentWildernessLevel = self.get('model.stonehearth:trapping_grounds.wilderness_level');
      
      if (currentWildernessLevel) {
         var color = currentWildernessLevel.heatmap_color;
         // use the heatmap color, except use a standard (reduced) alpha
         self.set('wildernessBackgroundColorStyle', `background-color: rgba(${color[0]},${color[1]},${color[2]},0.75)`)
      }
      else {
         self.set('wildernessBackgroundColorStyle', '')
      }
      self.set('currentWildernessLevel', currentWildernessLevel);
   }.observes('model.stonehearth:trapping_grounds.wilderness_level'),

   _updateTooltip: function() {
      var trappingGroundsData = this.get('currentTrappingGroundsData');
      var trappingGroundsTypeImage = this.$('#trappingGroundsTypeImage');
      if (trappingGroundsData && trappingGroundsTypeImage) {
         if (trappingGroundsTypeImage.hasClass('tooltipstered')) {
            trappingGroundsTypeImage.tooltipster('destroy');
         }
         trappingGroundsTypeImage.tooltipster({
            content: $('<div class=detailedTooltip><h2>' + i18n.t(trappingGroundsData.name) + '</h2>'
                        + i18n.t(trappingGroundsData.description) + '</div>')
         });
      }
   }.observes('currentTrappingGroundsData')
});
