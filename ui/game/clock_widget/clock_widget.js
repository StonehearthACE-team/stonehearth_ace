App.StonehearthCalendarView = App.View.extend({
   templateName: 'stonehearthCalendar',

   init: function() {
      this._super();
      var self = this;
      self.set('date', {});
      self.TIME_DURATIONS = {}
      self.TWO_DIGIT = '2-digit';

      $.get('/stonehearth/data/calendar/calendar_constants.json')
         .done(function(json) {
            self._constants = json;
            self.TIME_DURATIONS.second = 1
            self.TIME_DURATIONS.minute = self.TIME_DURATIONS.second * self._constants.seconds_per_minute
            self.TIME_DURATIONS.hour = self.TIME_DURATIONS.minute * self._constants.minutes_per_hour
            self.TIME_DURATIONS.day = self.TIME_DURATIONS.hour * self._constants.hours_per_day
            self.TIME_DURATIONS.month = self.TIME_DURATIONS.day * self._constants.days_per_month
            self.TIME_DURATIONS.year = self.TIME_DURATIONS.month * self._constants.months_per_year

            radiant.call('stonehearth:get_clock_object')
               .done(function(o) {
                  self.trace = radiant.trace(o.clock_object)
                     .progress(function(date) {
                        self.set('date', date);
                     })
               });
         });
      self._currentDay = null;
      self._currentDayOfYear = null;
      self._lastShownDayOfYear = null;

      radiant.call('stonehearth:get_service', 'seasons')
         .done(function (o) {
            self.seasons_trace = radiant.trace(o.result)
               .progress(function (o2) {
                  self.set('season', o2.current_season);
               })
         });

      // get a lookup of all the weather options by uri
      radiant.call('stonehearth_ace:get_all_weathers')
         .done(function (result) {
            self._all_weathers = result.weathers;
         });
   },

   willDestroyElement: function() {
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$().off('click', '#clock');
      this._super();
   },

   destroy: function() {
      this._super();
      if (this.trace) {
         this.trace.destroy();
         this.trace = null;
      }
      if (this.seasons_trace) {
         this.seasons_trace.destroy();
         this.seasons_trace = null;
      }
   },

   didInsertElement: function () {
      var self = this;

      self._tooltipDiv = null;
      self._dateObj = null;

      this._sun = $('#clock > #sun');
      this._sunBody = this._sun.find('#body');
      this._sunRays = this._sun.find('.ray');

      this._moon = $('#clock > #moon');
      this._moonBody = this._moon.find('#body');
      this._moonRays = this._moon.find('.ray');

      self._showingTooltip = false;

      $('#clock').tooltipster({
         position: 'left',
         updateAnimation: false,
         content: '',
         functionBefore: function(instance, proceed) {
            if (proceed) {
               self._showingTooltip = true;
               var gameSpeedData = App.gameView.getGameSpeedData();
               if (gameSpeedData.curr_speed === 0) {
                  self._updateClockTooltip(self.get('date'));
               }
               proceed();
            }
         },
         functionAfter: function(instance, proceed) {
            self._showingTooltip = false;
         }
      });

      $('#clock').click(function() {
         var hasModals = closeAllModalsRecursively();
         while(hasModals) {
            hasModals = closeAllModalsRecursively();
         }
         App.gameView.addView(App.StonehearthEscMenuView);
      })

      radiant.call('stonehearth:get_service', 'weather')
         .done(function (response) {
            self._weatherServiceUri = response.result;
            self._weatherTrace = new RadiantTrace(self._weatherServiceUri, { 'current_weather_state': {}, 'next_weather_types': {} })
               .progress(function (weatherService) {
                  if (!weatherService.current_weather_state) {
                     // No weather yet. Could happen during initialization.
                     self.set('weatherForecast', null);
                     return;
                  }

                  if (self.current_weather_stamp == weatherService.current_weather_stamp) {
                     return;
                  }
                  self.current_weather_stamp = weatherService.current_weather_stamp;

                  var days = [];
                  days.push({
                     uri: weatherService.current_weather_state.uri,
                     icon: weatherService.current_weather_state.icon,
                     prefix: 'stonehearth:ui.game.calendar.weather_prefix_0',
                  })
                  var FORECAST_DAYS = 2;
                  for (var i = 0; i < Math.min(FORECAST_DAYS, weatherService.next_weather_types.length); ++i) {
                     days.push({
                        uri: weatherService.next_weather_types[i].__self,
                        icon: weatherService.next_weather_types[i].icon,
                        prefix: 'stonehearth:ui.game.calendar.weather_prefix_' + (i + 1),
                     })
                  }

                  self.set('weatherForecast', days);

                  Ember.run.scheduleOnce('afterRender', this, function () {
                     self.$('.weatherDay').each(function () {
                        var el = $(this);
                        App.tooltipHelper.createDynamicTooltip(el, function() {
                           var uri = el.attr('data-uri');
                           var weather = self._all_weathers[uri];
                           if (weather) {
                              var description = i18n.t(weather.description);
                              if (weather.dynamic_weather) {
                                 // collect the icons from all the possible visible_to_user dynamic weathers
                                 var icons = '';
                                 radiant.each(weather.dynamic_weather, function(dynamicUri, conditions) {
                                    var dynamicWeather = self._all_weathers[dynamicUri];
                                    if (dynamicWeather && dynamicWeather.icon && !conditions.invisible_to_player) {
                                       icons += `<img class='inlineImg' src='${dynamicWeather.icon}'/>`;
                                    }
                                 });
                                 if (icons != '') {
                                    description += `<div>${i18n.t('stonehearth_ace:data.weather.dynamic')} <span class='weatherIcons'>${icons}</span></div>`;
                                 }
                              }
                              return $(App.tooltipHelper.createTooltip(
                                    i18n.t(el.attr('data-prefix')) + i18n.t(weather.display_name),
                                    description));
                           }
                        }, { position: 'bottom' });
                     });
                  });
               });
         });
   },

   getCalendarConstants: function() {
      return this._constants
   },

   getCurrentTime: function() {
      return this.get('date');
   },

   getRemainingTime: function(expireTimeInSeconds) {
      var currentTime = this.getCurrentTime();
      var secondsRemaining = expireTimeInSeconds - currentTime.elapsed_time;
      if (secondsRemaining <= 0) {
         return null;
      }

      var result = {};
      var calculationOrder = ['day', 'hour', 'minute', 'second'];
      for (var i=0; i < calculationOrder.length; ++i) {
         var timeUnit = calculationOrder[i];
         var timeUnitDuration = this.TIME_DURATIONS[timeUnit];
         if (secondsRemaining > timeUnitDuration) {
            var count = Math.floor(secondsRemaining / timeUnitDuration)
            secondsRemaining = secondsRemaining - (count * timeUnitDuration)
            result[timeUnit] = count;
         }
      }

      return result;
   },

   _updateClock: function() {
      var self = this;

      if (this._sun == undefined) {
         return;
      }

      var date = this.get('date');

      if (!date) {
         return;
      }

      if (date.elapsed_time < self._lastElapsedTime + 60 && date.second == self._lastSecond) {
         return;
      }

      self._lastElapsedTime = date.elapsed_time;
      self._lastSecond = date.second;

      if (date.day != self._currentDay) {
         self._currentDay = date.day;
         self._currentDayOfYear = date.day + date.month * self._constants.days_per_month;
         var dateAdjustedForStart = {
            day : date.day + 1,
            month : date.month + 1,
            year : date.year
         };
         self.set('dateAdjusted', dateAdjustedForStart);
      }

      var hoursRemaining;

      var sunriseTime = (this._constants.event_times.sunrise_start + this._constants.event_times.sunrise_end) / 2;
      if (date.hour >= sunriseTime && date.hour < this._constants.event_times.sunset_end) {
         hoursRemaining = this._constants.event_times.sunset_end - date.hour;

         if (this._hoursRemaining != hoursRemaining) {

            //transition to day
            this._moonBody.hide();
            this._moonRays.hide();
            this._sunBody.show();

            this._sun.find('#ray' + hoursRemaining).fadeIn();
            this._hoursRemaining = hoursRemaining;
         }

      } else {
         if (date.hour < sunriseTime) {
            hoursRemaining = sunriseTime - date.hour;
         } else {
            hoursRemaining = sunriseTime + this._constants.hours_per_day - date.hour;
         }

         if (this._hoursRemaining != hoursRemaining) {

            //transition to night
            this._sunBody.hide();
            this._sunRays.hide();
            this._moonBody.show();

            //show the moon, over and over...doh
            this._moonBody.show();
            this._sunRays.hide();
            this._sunBody.hide();

            this._moon.find('#ray' + hoursRemaining).fadeIn();
            this._hoursRemaining = hoursRemaining;
         }
      }

      if (self._showingTooltip) {
         self._updateClockTooltip(date);
      }
   }.observes('date'),

   _updateClockTooltip: function(date) {
      var self = this;

      if (!date) {
         return;
      }

      if (!self._dateObj) {
         self._dateObj = new Date(0, 0, 0, date.hour, date.minute);
      } else {
         self._dateObj.setHours(date.hour);
         self._dateObj.setMinutes(date.minute);
      }

      var localizedTime = self._dateObj.toLocaleTimeString(i18n.lng(), {hour: self.TWO_DIGIT, minute: self.TWO_DIGIT});
      if (!self._tooltipDiv) {
         var el = '<div id="clockTooltip">' + localizedTime + '</div>';
         self._tooltipDiv = $(el);
      } else {
         self._tooltipDiv.html(localizedTime);
      }

      self.$('#clock').tooltipster('content', self._tooltipDiv);
   },

   _updateSeasonImage: function() {
      var self = this;
      var season = self.get('season');
      var icon = season && season.id && stonehearth_ace.getSeasonIcon(season.id);
      self.set('seasonIcon', icon);
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
               if (remainingDays < 0) {   // ACE: just changed this from <= to < so it doesn't say 84 days to next season on the morning of a season change
                  remainingDays += self._constants.days_per_month * self._constants.months_per_year;
               }
               var remainingPart = remainingDays == 1 ? i18n.t('stonehearth:ui.game.calendar.season_reamining_day') : remainingDays == 0 ? i18n.t('stonehearth_ace:ui.game.calendar.season_no_reamining_days') : i18n.t('stonehearth:ui.game.calendar.season_reamining_days', { num: remainingDays });
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
   }.observes('dateAdjusted', 'season')   // ACE: also changed to observe dateAdjusted instead of date so self._currentDayOfYear is properly defined
});
