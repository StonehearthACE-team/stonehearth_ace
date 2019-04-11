App.StonehearthCalendarView.reopen({
   didInsertElement: function () {
      var self = this;
      self._super();

      var img = $('<img>')
         .addClass('seasonImage')
         .attr('id', 'seasonImage')
         .attr('onerror', 'this.style.display = "none"');//hides broken/missing icons
      self.$('#dateString')
         .append($('<br>'))
         .append(img);
      
      img.hide();
   },

   _updateSeasonImage: function() {
      var self = this;
      var season = self.get('season');
      if (season && season.id) {
         var icon = stonehearth_ace.getSeasonIcon(season.id);
         if (icon) {
            self.$('#seasonImage')
               .attr('src', icon)
               .show();
         }
      }
      else {
         self.$('#seasonImage').hide();
      }
   }.observes('season')
});