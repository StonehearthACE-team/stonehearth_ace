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
   }.observes('season'),

   _updateDateTooltip: function (date) {
      var self = this;
      var season = self.get('season');
      if (season && season.display_name && (self._currentSeason != season.id || self._currentDayOfYear != self._lastShownDayOfYear)) {
         Ember.run.scheduleOnce('afterRender', self, function () {
            self._currentSeason = season.id;
            self._lastShownDayOfYear = self._currentDayOfYear;

            var $e = self.$('#dateString');
            if ($e) {
               var remainingDays = season.end_day - self._currentDayOfYear;
               if (remainingDays < 0) {   // Paul: just changed this from <= to < so it doesn't say 84 days to next season on the morning of a season change
                  remainingDays += self._constants.days_per_month * self._constants.months_per_year;
               }
               var remainingPart = remainingDays == 1 ? i18n.t('stonehearth:ui.game.calendar.season_reamining_day') : i18n.t('stonehearth:ui.game.calendar.season_reamining_days', { num: remainingDays });
               var description = i18n.t(season.description) + '<br /><br />' + remainingPart;
               var content = $(App.tooltipHelper.createTooltip(i18n.t(season.display_name), description));
               
               if ($e.data('tooltipster')) {
                  $e.tooltipster('content', content);
               } else {
                  $e.tooltipster({ 'content': content, position: 'left' });
               }
            }
         });
      }
   }.observes('dateAdjusted', 'season')   // Paul: also changed to observe dateAdjusted instead of date so self._currentDayOfYear is properly defined
});