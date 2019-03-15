App.StonehearthTrappingGroundsView.reopen({
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

   init: function() {
      var self = this;
      self._super();

      self._trappingGroundsWildernessLevelChange();
   },
});
