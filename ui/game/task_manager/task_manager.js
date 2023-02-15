App.StonehearthTaskManagerView = App.View.extend({
   templateName: 'stonehearthTaskManager',

   init: function() {
      this._super();
      var self = this;
      self.set('context', {});

      radiant.call('radiant:get_task_manager')
            .progress(function (response) {
               self._lastData = response;
               self._refresh();
            });
   },

   didInsertElement: function () {
      var self = this;
      self.bars    = $('#taskManager').find('#meter');
      self.details = $('#taskManager').find('#details');

      self.bars.click(function () {
         self._populateDetails();
         $(self.details).toggle();
      });

      $(top).on("show_processing_meter_changed.task_manager", function (_, e) {
         if (e.value) {
            self.$('#stonehearthTerrainVision').removeClass('meter-hidden');
   
            // simply show the meter in the taskbar
            self.$('#meter').show();
         }
         else {
            // if we're hiding it, we need to make sure the details part is also hidden
            self.$('#details').hide();
            self.$('#meter').hide();
   
            self.$('#stonehearthTerrainVision').addClass('meter-hidden');
         }
      });

      Ember.run.scheduleOnce('afterRender', this, function() {
         stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_processing_meter', function(value) {
            $(top).trigger('show_processing_meter_changed', { value: value });
         });
      });
   },

   _refresh: $.throttle(100, function() {
      var self = this;
      if (!self.bars) {
         return;
      }

      var data = self._lastData;

      self.total_time_with_idle = 0

      $.each(data.counters, function(i, counter) {
         self.total_time_with_idle += counter.time;
      });
      if (self.total_time_with_idle == 0) {
         self.total_time_with_idle = 1;
      }

      var totalWidth = 0;
      var scale = 100 / self.total_time_with_idle;

      $.each(data.counters, function(i, counter) {
         var width = counter.time * scale
         totalWidth += width;

         if (counter.name === 'idle') {
            return;
         }

         var bar = self.bars.find('.' + counter.name);

         if (bar.length == 0) {
            bar = $('<div>')
               .addClass('counter')
               .addClass(counter.name);

            self.bars.append(bar)
         }
         bar.css('width', width);
         bar.css('min-width', width);
         bar.css('max-width', width);
      });
      self.bars.css('width', totalWidth);
      self.bars.css('min-width', totalWidth);
      self.bars.css('max-width', totalWidth);

      if (self.details.is(':visible')) {
         self._populateDetails();
      }
   }),

   _populateDetails: function() {
      var self = this;
      var data = self._lastData;

      $.each(data.counters, function(i, counter) {
         var row = self.details.find('#' + counter.name);
         var percent = (counter.time * 100.0 / self.total_time_with_idle).toFixed(1) + '%';

         if (row.length == 0) {
            self.details.find('table').append('<tr id=' + counter.name + '><td class="key ' + counter.name + '">&nbsp;&nbsp;<td class=name>' + counter.name + '<td class=time>' + percent + '</td>');
         } else {
            row.find('.time').html(percent);
         }
      });
   },

   destroy: function() {
      this._super();
      if (this.trace) {
         this.trace.destroy();
      }
      $(top).off("show_processing_meter_changed.task_manager");
   }
});
