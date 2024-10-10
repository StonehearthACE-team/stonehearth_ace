App.StonehearthTaskManagerView = App.View.extend({
   templateName: 'stonehearthTaskManager',

   DEF_USAGE_CLASS: 'noUsage',
   MAX_POINTS: 100,

   _totalTime: 0,
   _selectedCategory: 'idle',
   _selectedCategoryChart: null,
   _overallChart: null,
   _overallData: queue(),

   init: function() {
      this._super();
      var self = this;
      self.set('context', {});
      self.set('categories', []);

      radiant.call('radiant:get_task_manager')
            .progress(function (response) {
               self._lastData = response;
               self._refresh();
            });

      $.getJSON('/stonehearth_ace/ui/game/task_manager/categories.json', function(data) {
         self._categories = {};
         self._historicalData = {};
         radiant.each(data.categories, function(k, v) {
            self._categories[v] = {
               name: v,
               value: 0,
               usage: self.DEF_USAGE_CLASS
            };
            self._historicalData[v] = queue();
         });
         self.set('categories', radiant.map_to_array(self._categories));
      });
   },

   didInsertElement: function () {
      var self = this;
      self.bars    = $('#taskManager').find('#meter');
      self.details = $('#taskManager').find('#details');

      self.bars.click(function () {
         // if history is visible, clear out the charts so updating will no longer happen once we hide it
         var wasVisible = !$(self.details).hasClass('hidden');
         if (!wasVisible) {
            self._initCharts();
            $(self.details).removeClass('hidden');
         }
         else {
            $(self.details).addClass('hidden');
            self._selectedCategoryChart = null;
            self._overallChart = null;
            d3.select('#charts').selectAll('svg').remove();
         }
      });

      $(top).on("show_processing_meter_changed.task_manager", function (_, e) {
         if (e.value) {
            // make sure details are hidden before reshowing
            $(self.details).addClass('hidden');
            self.$('#taskManager').show();
         }
         else {
            // just hide the whole thing!
            self.$('#taskManager').hide();
         }
      });

      Ember.run.scheduleOnce('afterRender', this, function() {
         stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_processing_meter', function(value) {
            $(top).trigger('show_processing_meter_changed', { value: value });
         });
      });

      App.guiHelper.createDynamicTooltip(self.$('#categories'), '.category', function($el) {
         var category = $el.attr('category');
         var tooltip = App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.task_manager.categories.' + category));
         return $(tooltip);
      }, {delay: 500});
   },

   // based on https://bost.ocks.org/mike/path/
   _createChart: function(containerId, heightFactor) {
      var self = this;

      var myData;
    
      var margin = {top: 16, right: 0, bottom: 6, left: 50},
         width = 300 - margin.right,
         height = 90 * heightFactor - margin.top - margin.bottom;
    
      var x = d3.scale.linear()
         .domain([0, self.MAX_POINTS])
         .range([0, width]);
    
      var y = d3.scale.linear()
         .domain([0, 1])
         .range([height, 0]);

      var formatPercent = d3.format(".0%");
    
      var line = d3.svg.line()
         .interpolate("linear")
         .x(function(d, i) { return x(i); })
         .y(function(d, i) { return y(d); });
    
      var svg = d3.select(containerId).append("p").append("svg")
         .attr("width", width + margin.left + margin.right)
         .attr("height", height + margin.top + margin.bottom)
         .style("margin-left", -margin.left + "px")
       .append("g")
         .attr("transform", "translate(" + margin.left + "," + margin.top + ")");
    
      svg.append("defs").append("clipPath")
         .attr("id", "clip")
        .append("rect")
         .attr("width", width)
         .attr("height", height);

      svg.append("g")
         .attr("class", "y axis")
         .call(d3.svg.axis().scale(y).ticks(5).orient("left").tickFormat(formatPercent));

      svg.selectAll("line.horizontalGrid").data(y.ticks(5)).enter()
         .append("line")
            .attr(
            {
                  "class":"horizontalGrid",
                  "x1" : margin.right,
                  "x2" : width,
                  "y1" : function(d){ return y(d);},
                  "y2" : function(d){ return y(d);},
                  "shape-rendering" : "crispEdges",
            });

      var path = svg.append("g")
         .attr("clip-path", "url(#clip)")
        .append("path")
         .attr("class", "line")
         .datum([])
         .attr("d", line);

      var text = svg.append("text")
        .attr("x", (width / 2))             
        .attr("y", 0 - (margin.top / 2))
        .attr("text-anchor", "middle")
        .attr("class", "title");
    
      return {
         setData: (data, title) => {
            myData = data;
            path.datum(data);
            text.text(title);
         },
         addPoint: (value) => {
            myData.push(value);
            path.attr("d", line);
            path.attr("transform", null);
            if (myData.length > self.MAX_POINTS) {
               path.transition()
                  .ease("linear")
                  .attr("transform", "translate(" + x(-1) + ")");
               myData.shift();
            }
         }
      }
   },

   _refresh: $.throttle(100, function() {
      var self = this;
      if (!self.bars) {
         return;
      }

      var data = self._lastData;
      self._totalTime++;

      self.total_time_with_idle = 0

      var totalWithoutIdle = 0;
      $.each(data.counters, function(i, counter) {
         self.total_time_with_idle += counter.time;
         if (counter.name !== 'idle') {
            totalWithoutIdle += counter.time;
         }
      });
      if (self.total_time_with_idle == 0) {
         self.total_time_with_idle = 1;
      }

      // cache latest data (normalized) in historical data structure
      var normalizedData = {};
      var normalizedArr = [];
      var maxUsage = 0;
      radiant.each(data.counters, function(i, counter) {
         var normalized = counter.time / self.total_time_with_idle;
         maxUsage = Math.max(maxUsage, normalized);
         self._historicalData[counter.name].push(normalized);
         normalizedData[counter.name] = normalized;
         normalizedArr.push([counter.name, normalized]);
      });

      var normalizedTotal = totalWithoutIdle / self.total_time_with_idle;
      self._overallData.push(normalizedTotal);
      normalizedArr.sort(function(a, b) {
         return b[1] - a[1];
      });

      var categoryUsages = {};
      radiant.each(normalizedArr, function(i, v) {
         var category = v[0];
         var usage = v[1];
         if (usage == 0) {
            categoryUsages[category] = 'noUsage';
         }
         else if (usage >= 0.05) {
            categoryUsages[category] = 'someUsage';
         }
         else {
            categoryUsages[category] = 'lowUsage';
         }
      });
      categoryUsages[normalizedArr[0][0]] = 'topUsage';

      if (self._selectedCategoryChart) {
         self._selectedCategoryChart.addPoint(normalizedData[self._selectedCategory]);
      }
      if (self._overallChart) {
         self._overallChart.addPoint(normalizedTotal);
      }

      if (self._totalTime > self.MAX_POINTS) {
         radiant.each(self._historicalData, function(k, v) {
            v.shift();
         });
         self._overallData.shift();
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

      if (!$(self.details).hasClass('hidden')) {
         radiant.each(self._categories, function(k, v) {
            //var opacity = Math.max(self.MIN_OPACITY, self.MIN_OPACITY + (1 - self.MIN_OPACITY) * (v.value / maxUsage));
            Ember.set(v, 'usage', categoryUsages[k]);
            var percent = (normalizedData[k] * 100).toFixed(1) + '%';
            Ember.set(v, 'value', percent);
         });
      }
   }),

   _initCharts: function() {
      var self = this;
      var data = self._historicalData;

      if (!self._overallChart) {
         self._overallChart = self._createChart('#overallChart', 1);
         self._overallChart.setData(self._overallData.toArray(), "Overall Usage");
      }

      if (!self._selectedCategoryChart) {
         self._selectedCategoryChart = self._createChart('#selectedCategoryChart', 2);
         self._selectedCategoryChart.setData(data[self._selectedCategory].toArray(), self._selectedCategory);
      }
   },

   destroy: function() {
      this._super();
      if (this.trace) {
         this.trace.destroy();
      }
      $(top).off("show_processing_meter_changed.task_manager");
   },

   actions: {
      selectCategory: function(category) {
         var self = this;
         // if a different category is already selected, we need to change the chart's data
         if (self._selectedCategory !== category) {
            self.$('#selectedCategoryChart').removeClass(self._selectedCategory);
            self._selectedCategory = category;
            self.$('#selectedCategoryChart').addClass(self._selectedCategory);
            self._selectedCategoryChart.setData(self._historicalData[category].toArray(), self._selectedCategory);
         }
      }
   }
});
