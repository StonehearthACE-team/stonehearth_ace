App.StonehearthCalendarView.reopen({
   didInsertElement: function () {
      var self = this;
      self._super();

      var img = $('<img>')
         .addClass('seasonImage')
         .attr('id', 'seasonImage');
      self.$('#dateString')
         .append($('<br>'))
         .append(img);
      
      img.hide();
   },

   _updateSeasonImage: function() {
      var self = this;
      var season = self.get('season');
      if (season && season.id) {
         self.$('#seasonImage')
            .attr('src', '/stonehearth_ace/ui/game/modes/zones_mode/farm/images/property_season_' + season.id + '.png')
            .show();
      }
      else {
         self.$('#seasonImage').hide();
      }
   }.observes('season')
});