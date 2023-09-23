$(document).ready(function() {
   $(top).on("radiant_open_character_sheet", function(_, e) {
      // ACE: maintain character sheet game view in stonehearthClient
      // showing and hiding rather than recreating it every time
      App.stonehearthClient.showCharacterSheet(e.entity);
   });
});

App.StonehearthCitizenCharacterSheetView = App.View.extend({
   templateName: 'citizenCharacterSheet',
   uriProperty: 'model',
   closeOnEsc: true,
   APPEAL_BAR_WIDTH: 650,

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:buffs' : {
         'buffs' : {
            '*' : {}
         }
      },
      'stonehearth:traits' : {
         'traits': {
            '*' : {}
         }
      },
      'stonehearth:equipment' : {
         'equipped_items' : {
            '*' : {
               'stonehearth:item_quality': {},
               'uri': {}
            }
         }
      },
      'stonehearth:attributes' : {},
      'stonehearth:expendable_resources' : {},
      'stonehearth:personality' : {},
      'stonehearth:score' : {},
      'stonehearth:happiness': {
         'current_mood_buff': {}
      },

      'stonehearth:job' : {
         'curr_job_controller' : {},
         'job_controllers' : {
            '*' : {}
         }
      },
      'stonehearth:storage' : {
         'item_tracker' : {
            'tracking_data': {
               'stonehearth:loot:gold' : {
                  'items' : {
                     '*' : {
                        'stonehearth:stacks': {}
                     }
                  }
               }
            }
         }
      },
      'stonehearth:appeal': {},
      'stonehearth:teleportation': {},
      // ACE: added titles
      'stonehearth_ace:titles': {}
   },

   init: function() {
      var self = this;
      self._super();
      self.set('equipment', {});
      self._createJobDataArray();
      self._createMoodBarTooltipTemplate();
   },

   dismiss: function () {
      this.set('uri', null);

      var index = App.stonehearth.modalStack.indexOf(this)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }

      this.hide();
   },

   show: function () {
      this._super();

      App.stonehearth.modalStack.push(this);
   },

   //When we get job data from the server, turn maps into arrays and store in allJobData
   _createJobDataArray: function() {
      var self = this;
      var jobArray = radiant.map_to_array(App.jobConstants);
      self.set('allJobData', jobArray);
   },

   //Updates job related attributes
   _updateJobData : function() {
      if (!this.get('uri')) return;

      this.set('currJobIcon', this.get('model.stonehearth:job.class_icon'));
      Ember.run.scheduleOnce('afterRender', this, '_updateAttributes');
   }.observes('model.stonehearth:job'),

   //Updates perk table
   _updateJobDataDetails: function() {
      if (!this.get('uri')) return;
      
      Ember.run.scheduleOnce('afterRender', this, '_updateJobsAndPerks');
   }.observes('model.stonehearth:job.curr_job_controller'),

   _updateJobDescription: function() {
      if (!this.get('uri')) return;
      
      // Force the unit info description to update again after curr job name changes.
      // This used to work (or I never noticed.) but now the timing is such that the description change comes in before the job name. -yshan 1/19/2016
      var description = this.get('model.stonehearth:unit_info.description');
      if (description) {
         this.set('model.stonehearth:unit_info.description', ''); // Sigh, you have to clear it out or ember won't actually send a value changed message.
         this.set('model.stonehearth:unit_info.description', description);
      }
   }.observes('model.stonehearth:job.curr_job_name'),

   _updateHappiness : function() {
      if (!this.get('uri')) return;
      
      var self = this;
      if (!self._segmentsInitialized) {
         self._initMoraleBarSegments();
         self._segmentsInitialized = true;
      }
      self._updateMoodBarTooltips();
      self._updateMoraleArrow();
      self._updateThoughtEntries();
   }.observes('model.stonehearth:happiness'),

   _initMoraleBarSegments : function() {
      var self = this;
      var thresholds = self.get('model.stonehearth:happiness.mood_thresholds');
      var constants = App.happinessConstants;
      var barWidth = constants.ui.happiness_bar_width;
      var minProportion = Math.floor((constants.ui.min_segment_width / barWidth) * 100) / 100; // bar proportion

      var moodsList = constants.moods;
      var totalWidth = constants.max_happiness;
      var remainderProportion = 1 - minProportion * moodsList.length; // remainder left after allocating each mood the min width

      // the widths we allocate for each mood segment in the morale bar
      self._moodBarSegmentWidths = {}
      var remainingWidth = barWidth;
      var prevMoodThreshold = constants.min_happiness;
      for (var i = 0; i < moodsList.length; i++) {
         var mood = moodsList[i];
         var moodThreshold = thresholds[mood] || constants.max_happiness;
         var desiredWidth = moodThreshold - prevMoodThreshold;
         prevMoodThreshold = moodThreshold;
         var calculatedProportion = (desiredWidth / totalWidth) * remainderProportion + minProportion; // proportion of the bar that this segment will take up
         var width = Math.floor(calculatedProportion * barWidth); // get width of the segment in pixels
         self._moodBarSegmentWidths[mood] = width;
         remainingWidth -= width;
      }

      if (remainingWidth > 0) { // had some remaining width to fill bar, so arbitrarily add to last segment
         self._moodBarSegmentWidths[moodsList.length - 1] += remainingWidth;
      }

      var currentMood = self.get('model.stonehearth:happiness.mood');
      // add bar segments based on the mood widths calculated above
      $('#barSegments').empty(); // clear barSegment children divs
      radiant.each(constants.mood_data, function(mood, moodData) {
         self._appendBarSegment(mood, moodData, currentMood, self._moodBarSegmentWidths[mood]);
      });
   },

   _appendBarSegment: function(mood, moodData, currentMood, barWidth) {
      var widthStyle = 'width: ' + barWidth + 'px;';
      var backgroundStyle = 'background: ' + moodData.bar_color + ';';
      var inactiveClass = mood !== currentMood ? 'inactiveMood' : '';
      var icon = $('<img class="moodBarIcon">')
         .attr('src', moodData.icon);

      var segmentShade = $('<div class="segmentShade">')
         .attr('style', widthStyle)
         .addClass(inactiveClass);

      var barShade = $('<div class="barShade">')
         .attr('style', widthStyle);

      var segment = $('<div class="moodBarSegment">')
         .attr('mood', mood)
         .attr('style', widthStyle + backgroundStyle)
         .append(icon)
         .append(barShade)
         .append(segmentShade);

      $('#barSegments').append(segment);
   },

   _updateMoodBarTooltips: function() {
      var self = this;
      if (!self._moodBarTooltipTemplate) {
         return;
      }
      $('.moodBarSegment').each(function (index) {
         var $e = $(this);
         App.tooltipHelper.createDynamicTooltip($e, function () {
            var happiness = self.get('model.stonehearth:happiness');
            if (happiness) {
               return $(self._makeMoodBarTooltip(happiness, $e.attr("mood"), index));
            }
         });
      });
   },

   // Create mood bar tooltip string
   _makeMoodBarTooltip: function(happinessData, hoveredMood, index) {
      var thresholds = happinessData.mood_thresholds;
      var threshold = thresholds[hoveredMood];
      var thresholdStr = '';
      if (threshold < thresholds['content']) {
         thresholdStr = i18n.t('stonehearth:ui.game.citizen_character_sheet.below') + ' ' + threshold;
      } else {
         thresholdStr = i18n.t('stonehearth:ui.game.citizen_character_sheet.above') + ' ' + thresholds[App.happinessConstants.moods[index - 1]];
      }

      // Pass in context for evaluating template. Would normally i18n in the template itself,
      // but regular Handlebars isn't able to run the i18n helper
      var context = {
         currently: i18n.t('stonehearth:ui.game.citizen_character_sheet.currently'),
         currentMood: i18n.t(App.tooltipHelper.getTooltipData(happinessData.mood).display_name),
         hoveredMood: i18n.t(App.tooltipHelper.getTooltipData(hoveredMood).display_name),
         hoveredMoodDescription: i18n.t(App.tooltipHelper.getTooltipData(hoveredMood).description),
         currentHappiness: Math.round(happinessData.current_happiness),
         threshold: thresholdStr
      };

      return this._moodBarTooltipTemplate(context);
   },

   // Compile a template that can be executed later with context for the mood bar tooltips
   _createMoodBarTooltipTemplate: function() {
      var self = this;
      $.get('/stonehearth/ui/game/character_sheets/citizen_character_sheet/mood_bar_tooltip_template.html')
         .done(function(html) {
            // Used vanilla Handlebars to compile this template because Ember.Handlebars.compile has problems
            // evaluating property templates, assumes they are helpers
            self._moodBarTooltipTemplate = Handlebars.compile(html);
         });
   },

   _calculateDuration: function(endTime) {
      if (!endTime) {
         return null;
      }

      var calendarView = App.gameView.getView(App.StonehearthCalendarView);
      var currentTime = calendarView.getCurrentTime().elapsed_time;

      var timeInSeconds = endTime - currentTime;
      var days = Math.floor(timeInSeconds/calendarView.TIME_DURATIONS['day']);
      if (days > 0) {
         return days + 'd';
      } else {
         return Math.ceil(timeInSeconds/calendarView.TIME_DURATIONS['hour']) + 'h';
      }
   },

   _thoughtsChanged: function(newThoughtSummary) {
      var self = this;

      if (self._thoughtSummary == null) {
         return true;
      }

      if (!_.isEqual(Object.keys(newThoughtSummary), Object.keys(self._thoughtSummary))) {
         return true;
      }


      var changed = false;
      radiant.each(self._thoughtSummary, function(key, value) {
         if (value.duration != self._calculateDuration(newThoughtSummary[key].end_time)) {
            changed = true;
         }
      });

      return changed;
   },

   _updateThoughtEntries: function() {
      var self = this;

      var thoughtSummary = self.get('model.stonehearth:happiness.thought_summary');
      // check if the thought summary is equal on a key-value level. ideally we would only trigger
      // updateThoughtEntries in the event that the thought summary has changed from the happiness
      // component, but the ember observer is triggered every time saved_variables are marked changed


      if (!self._thoughtsChanged(thoughtSummary)) {
         return;
      }
      
      self._thoughtSummary = thoughtSummary;
      var negativeThoughts = [];
      var positiveThoughts = [];

      radiant.each(self._thoughtSummary, function (key, value) {
         Ember.set(value, 'duration', self._calculateDuration(value.end_time));

         if (self._convertDuration(value.duration) < 0) {
            // Citizens dispatched on quests have their happiness component paused,
            // so outdated thoughts may stick around. Ignore them.
            return;
         }

         if (value.data.happiness_delta < 0) {
            negativeThoughts.push(value);
         } else {
            positiveThoughts.push(value);
         }
      });

      negativeThoughts.sort(function(a,b){
         var diff = a.data.happiness_delta - b.data.happiness_delta;
         if (diff === 0) {
            return self._convertDuration(b.duration) - self._convertDuration(a.duration);
         }
         return diff;
      });
      positiveThoughts.sort(function(a,b){
         var diff = b.data.happiness_delta - a.data.happiness_delta;
         if (diff === 0) {
            return self._convertDuration(b.duration) - self._convertDuration(a.duration);
         }
         return diff;
      });

      self.set('positiveThoughts', positiveThoughts);
      self.set('negativeThoughts', negativeThoughts);
      Ember.run.scheduleOnce('afterRender', self, '_updateThoughtTooltips');
   },

   _convertDuration: function(duration) {
      if (!duration) {
         return 0;
      }
      if ((typeof duration) === 'string') {
         var period = duration.slice(-1); // get the period ('h' or 'd')
         var n = parseInt(duration.substring(0, duration.length - 1)); // get the duration number
         if (period === 'd') {
            n *= 24;
         }
         return n; // return value in game hours
      }

      return 0;
   },

   _updateMoraleArrow : function() {
      var self = this;
      var happinessData = self.get('model.stonehearth:happiness');
      var happiness = happinessData.current_happiness;
      if (happiness == self._currentHappiness) {
         return; // no update needed
      }
      var constants = App.happinessConstants;
      var currentMood = happinessData.mood;
      var thresholds = happinessData.mood_thresholds;
      self._currentHappiness = happiness;

      // dim the inactive moods in the morale bar
      if (currentMood != self._currentMood) {
         radiant.each(constants.moods, function(_, mood) {
            var element = $('[mood=' + mood + '] > .segmentShade');
            if (element) {
               if (mood == currentMood) {
                  element.removeClass('inactiveMood');
               } else {
                  element.addClass('inactiveMood');
               }
            } else {
               console.log('could not find the segmentShade div for ' + mood);
            }
         });
      }
      self._currentMood = currentMood;

      // calculate position of the morale bar's mood indicator arrow, based on the mood segment widths
      var hidePressure = false;
      var moodsList = constants.moods;
      var leftSegmentPosition = 0;
      for (var i = 0; i < moodsList.length; i++) {
         var mood = moodsList[i];
         var segmentWidth = self._moodBarSegmentWidths[mood];
         if (mood == currentMood) {
            var maxThreshold = thresholds[mood] || constants.max_happiness;
            var prevThreshold = i - 1 >= 0 ? thresholds[moodsList[i-1]] : 0;
            var position = leftSegmentPosition + ((happiness - prevThreshold) / (maxThreshold - prevThreshold)) * segmentWidth;
            position = Math.min(Math.max(position, constants.ui.mood_bar_min_left), constants.ui.mood_bar_max_left);
            self.set('morale_arrow_style', 'left: ' + position + 'px; display: block');
            if (position == constants.ui.mood_bar_min_left || position == constants.ui.mood_bar_max_left) {
               hidePressure = true; // the arrow is at the end of the bar, so don't show the pressure indicator since the arrow can't move any further
            }
            break;
         }
         leftSegmentPosition += segmentWidth;
      }

      // update the pressure marker that indicates what direction a hearthling's happiness is going
      var marker = '';
      var currentPressure = happinessData.current_pressure;
      // only change the pressure marker image if the pressure has changed
      if (self._currentPressure !== currentPressure) {
         self._currentPressure = currentPressure;
         // set velocity marker indicator on happiness bar, showing which direction a hearthling's happiness is going
         if (!hidePressure && Math.abs(currentPressure - constants.min_pressure) > constants.ui.show_pressure_marker_threshold) {
            var pressureDirection = currentPressure < constants.min_pressure ? 'decrease' : 'increase';
            $('#happinessBarPressureMarker').removeClass().addClass(pressureDirection + 'Pressure');
            radiant.each(constants.pressure_markers, function(ticks, d) {
               var abs = Math.abs(currentPressure);
               if ((abs > d.threshold.min) && (d.threshold.max ? abs <= d.threshold.max : true)) {
                  var pressureMarker = '/stonehearth/ui/game/character_sheets/citizen_character_sheet/images/mood_'
                                       + pressureDirection + '_' + ticks + '.png';
                  marker = 'background-image: url(' + pressureMarker + ')';
                  return false; // break from each loop
               }
            });
         }
      }
      self.set('model.pressure_marker_style', marker);
   },

   _updateThoughtTooltips : function() {
      var self = this;
      $('#thoughtEntries .thoughtEntryData').each(function (index, data) {
         var $e = $(this);
         App.tooltipHelper.createDynamicTooltip($e, function () {
            var name = $e.attr('title');
            var key = $e.attr('key');
            // shallow copy because i18n adds a postProcess field to the tooltip_args, which causes the thought summary equality check to fail
            if (self._thoughtSummary[key]) {
               var tooltipArgs = radiant.shallow_copy(self._thoughtSummary[key].tooltip_args);
               var tooltipString = "<div>" + i18n.t(name, tooltipArgs) + "</div>";
               return $(tooltipString)
            } else {
               return null;
            }
         });
      });
   },

   // ACE: better handle worker job, population override jobs, and whether or not the job has perks
   //Go through each job we've had and annotate the perk table accordingly
   _updateJobsAndPerks : function() {
      var self = this;

      //Hide all the job divs before selectively showing the ones for the current
      //character.
      if (!self.$('.jobData')) {
         return; // this can happen if character is destroyed.
      }

      self.$('.jobData').hide();

      //show each class that this person has ever been
      var allJobData = App.jobConstants;
      var jobs = this.get('model.stonehearth:job.job_controllers');
      var workerDivs = [];
      radiant.each(jobs, function(alias, data) {
         var job_alias = data.json_path;
         var isWorker = job_alias == 'stonehearth:jobs:worker';
         var hasPerks = job_alias != 'stonehearth:jobs:worker';
         var jobData = allJobData[job_alias];
         if (jobData) {
            isWorker = jobData.description.is_worker;
            hasPerks = self._hasPerks(jobData.description);
         }
         else {
            job_alias = alias;
            isWorker = job_alias == 'stonehearth:jobs:worker';
            hasPerks = job_alias != 'stonehearth:jobs:worker';
            jobData = allJobData[job_alias];
            if (jobData) {
               isWorker = jobData.description.is_worker;
               hasPerks = self._hasPerks(jobData.description);
            }
         }

         if (hasPerks) {
            var div = self.$("[uri='" + job_alias + "']");

            //For each, figure out which perks should be unlocked
            self._unlockPerksToLevel(div, data.last_gained_lv)

            $(div).show();

            if (isWorker) {
               workerDivs.push(div);
            }
         }
      });

      //Highlight current class, since it needs to be 100% up to date
      self.$('.activeClassNameHeader').removeClass('activeClassNameHeader');
      self.$('.className').addClass('retiredClassNameHeader');
      self.$('.jobData').addClass('retiredEffect');
      var currClassAlias = this.get('model.stonehearth:job.job_json_path');
      var $currClass = self.$("[uri='" + currClassAlias + "']");
      $currClass.prependTo("#citizenCharacterSheet #abilitiesTab");
      $currClass.find('.className').removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      $currClass.removeClass('retiredEffect');
      //$currClass.removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      self._unlockPerksToLevel($currClass,  this.get('model.stonehearth:job.curr_job_controller.last_gained_lv'))
      $currClass.find('.retiredAt').hide();

      workerDivs.forEach(div => {
         div.find('.retiredAt').hide();
      });

      //Make the job tooltips
      this._updateJobTooltips();
   },

   _hasPerks: function (jobDescription) {
      var hasPerks = false;
      if (jobDescription.levelArray) {
         jobDescription.levelArray.forEach(levelData => {
            if (levelData.perks && levelData.perks.length > 0) {
               hasPerks = true;
            }
         });
      }
      return hasPerks;
   },

   //Given a perk div and target level, change the classes within to reflect the current level
   _unlockPerksToLevel : function (target_div, target_level) {
      $(target_div).find('.levelLabel').addClass('lvLabelLocked');
      $(target_div).find('img').addClass('perkImgLocked');
      for(var i=0; i<=target_level; i++) {
         $(target_div).find("[imgLevel='" + i + "']").removeClass('perkImgLocked').addClass('perkImgUnlocked');
         $(target_div).find("[lbLevel='" + i + "']").removeClass('lvLabelLocked').addClass('lvLabelUnlocked');
         $(target_div).find("[divLevel='" + i + "']").attr('locked', "false");
      }

      //For good measure, throw the level into the class name header or remove if the level is 0
      if (target_level >= 0 && target_level <= 2) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.apprentice'));
      } else if (target_level >= 3 && target_level <= 4) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.journeyman'));
      } else if (target_level >= 5) {
         $(target_div).find('.lvlTitle').text(target_level + ', ' + i18n.t('stonehearth:ui.game.citizen_character_sheet.master'));
      }

      //Calculate the height of the jobPerks section based on the number of perkDivs
      //TODO: factor these magic numbers out or change if/when the icons change size
      // var numPerks = $(target_div).find('.perkDiv').length;
      // if (numPerks == 0) {
      //    $(target_div).find('.jobPerks').css('height', '0px');
      // } else {
      //    var num_rows = parseInt(numPerks/8) + 1;
      //    var total_height = num_rows * 90;
      //    $(target_div).find('.jobPerks').css('height', total_height + 'px');
      // }

      $(target_div).find('.retiredAt').show();
   },

   //Make tooltips for the perks
   _updateJobTooltips : function() {
      var self = this;
      App.tooltipHelper.createDynamicTooltip($('.tooltip'));
      $('.perkDiv').each(function (index) {
         var $e = $(this);
         App.tooltipHelper.createDynamicTooltip($e, function () {
            var perkName = $e.attr('name');
            var perkDescription = $e.attr('description');
            var tooltipString = '<div class="perkTooltip"> <h2>' + i18n.t(perkName);

            //If we're locked then add the locked label
            if ($e.attr('locked') == "true") {
               tooltipString = tooltipString + '<span class="lockedTooltipLabel">' + i18n.t('stonehearth:ui.game.citizen_character_sheet.locked_status') + '</span>';
            }

            tooltipString = tooltipString + '</h2>' + i18n.t(perkDescription) + '</div>';

            return $(tooltipString);
         });
      });
   },

   _setFirstJournalEntry: function() {
      if (!this.get('uri')) return;
      
      var log = this.get('model.stonehearth:personality.todays_log');
      var maxEntries = 3;

      var todaysJournalEntries = [];
      var todaysDate = null;
      if (log && log.entries) {
         todaysDate = i18n.t('stonehearth:ui.game.calendar.date_format_long', {date: log.date});

         for (var i=log.entries.length-1; i>=0 && todaysJournalEntries.length < maxEntries; i--) {
            var targetEntry = log.entries[i];
            todaysJournalEntries.push(
               {
                  title: i18n.t(targetEntry.title, {entry: targetEntry}),
                  text: i18n.t(targetEntry.text, {entry: targetEntry}),
                  has_score: targetEntry.scoreData != null,
                  is_good: targetEntry.scoreData != null ? targetEntry.scoreData.score_mod > 0 : null,
               }
            );
         }
      }

      this.set('journalEntryDate', todaysDate);
      this.set('journalEntries', todaysJournalEntries);
   }.observes('model.stonehearth:personality'),

   _buildTraitsArray: function() {
      if (!this.get('uri')) return;
      
      var traits = [];
      var traitMap = this.get('model.stonehearth:traits.traits');

      if (traitMap) {
         traits = radiant.map_to_array(traitMap);
         traits.sort(function(a, b){
            var aUri = a.uri;
            var bUri = b.uri;
            var n = aUri.localeCompare(bUri);
            return n;
         });
      }

      this.set('traits', traits);
   }.observes('model.stonehearth:traits'),

   _setEquipmentData: function() {
      if (!this.get('uri')) return;
      
      var self = this;
      var slots = App.characterSheetEquipmentSlots;
      var equipment = self.get('model.stonehearth:equipment.equipped_items');
      var allEquipment = [];
      radiant.each(slots, function(i, slot) {
         var equipmentPiece = equipment[slot];
         if (equipmentPiece) {
            var alias = equipmentPiece.get('uri').__self;
            var catalogData = App.catalog.getCatalogData(alias);
            if (catalogData && catalogData.display_name) {
               var quality = Math.max(1, equipmentPiece.get('stonehearth:item_quality.quality') || 1);
               var equipmentInfo = {
                  equipment: equipmentPiece,
                  display_name: catalogData.display_name,
                  description: catalogData.description,
                  icon: catalogData.icon,
                  quality: quality,
                  qualityClass: quality > 1 ? `quality-${quality}-icon` : 'hidden',
                  slotId: slot + 'Slot',
               }
               allEquipment.push(equipmentInfo);
            }
         }
      });
      self.set('all_equipment', allEquipment);
   }.observes('model.stonehearth:equipment.equipped_items'),

      _equipmentUpdatedListener: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         self._updateEquipmentTooltips();
      });
   }.observes('all_equipment'),

   _updateEquipmentTooltips: function() {
      var self = this;
      var all_equipment = self.get('all_equipment');
      radiant.each(all_equipment, function(i, equipmentInfo) {
         var equipmentRow = self.$('#' + equipmentInfo.slotId);
         var equipmentPiece = equipmentInfo.equipment;
         if (equipmentRow && equipmentRow.length != 0) {
            App.tooltipHelper.createDynamicTooltip(equipmentRow, function () {
               var tooltipString = '';
               tooltipString = '<div class="detailedTooltip"> <h2>' + i18n.t(equipmentInfo.display_name)
                                       + '</h2>' + i18n.t(equipmentInfo.description) + '</div>';
               return $(tooltipString);
            });
         }
      });
   },

      //When the attribute data changes, update the bars
   _setAttributeData: function() {
      if (!this.get('uri')) return;
      
      Ember.run.scheduleOnce('afterRender', this, '_updateAttributes');
   }.observes('model.stonehearth:attributes' , 'model.stonehearth:buffs'),

   _updateAttributes: function() {
      var self = this;
      if (self.isDestroyed || self.isDestroying) {
         return;
      }
      var buffsByAttribute = this._sortBuffsByAttribute();
      
      //HACK: Make inspiration show as a +/- %
      var inspirationValue = self.get('model.stonehearth:attributes.attributes.inspiration.user_visible_value');
      var inspirationDisplay = (inspirationValue < 0 ? '':'+') + inspirationValue + "%";
      self.set('inspiration_display_value',inspirationDisplay);

      if (!self.$()) {
         return;
      }

      // set the tooltip and text colors for attributes
      self.$('.attr').each(function(){
         var attributeName = $(this).attr('id');

         $(this).children('.attrName').each(function() {
            self._showAttributeTooltip(this, buffsByAttribute, attributeName);
         });

         // only change text color for attribute value divs depending on the buff effect
         $(this).children('.attrValue').each(function() {
            self._showAttributeTooltip(this, buffsByAttribute, attributeName);
            self._showBuffEffects(this, buffsByAttribute, attributeName);
         });
      });

      self.$('#glass > div').each(function() {
         var attributeName = $(this).attr('id');
         self._showAttributeTooltip(this, buffsByAttribute, attributeName);
         self._showBuffEffects(this, buffsByAttribute, attributeName);
      });
   },

   // update exp bar progress
   _updateExp: function() {
      if (!this.get('uri')) return;
      
      var self = this;
      var expData = radiant.getExpPercentAndLabel(self.get('model.stonehearth:job'));
      if (expData) {
         var expPercent = expData.percent;
         var expLabel = expData.label;

         self.set('model.exp_bar_style', 'width: ' + expPercent + '%');
         self.set('model.exp_bar_label', expLabel);
      }
   }.observes('model.stonehearth:job.curr_job_controller'),

   // list of what kind of resources we can display for this entity
   // first item is the default resource
   expendableResources: [
      'health',
      'guts'
   ],

   // update the health indicator icon
   _updateExpendableResource: function() {
      if (!this.get('uri')) return;
      
      var self = this;
      var constants = App.uiConstants.expendable_resources;
      var currentBuffs = self.get('model.stonehearth:buffs.buffs');
      var resourcePercentages = self.get('model.stonehearth:expendable_resources.resource_percentages');
      var resourceName, resourcePercentage;

      if (!resourcePercentages) {
         return;
      }

      for (var i = 0; i < self.expendableResources.length; i++) {
         var name = self.expendableResources[i];
         var percentage = resourcePercentages[name];
         // use the first resource that is active (non-zero) on the entity
         if (percentage > 0) {
            resourceName = name;
            resourcePercentage = percentage;
            break;
         }
      }

      if (!resourceName) {
         return;
      }

      var resourceData = constants[resourceName];
      var statusLabel = resourceData.status;
      var resourceImages = resourceData.current_player.static;
      // TODO: get state directly from the incapacitation component once state machine implementation is in
      // if resource is based on which health status buff is on the entity, update label and resource images accordingly
      if (resourceData.buffs_to_resource) {
         if (currentBuffs) {
            radiant.each(resourceData.buffs_to_resource, function(buffName, resourceImageKey){
               var buff = currentBuffs[buffName];
               if (buff) {
                  statusLabel = buff.display_name;
                  resourceImages = resourceData.current_player[resourceImageKey];
                  return false;
               }
            });
         } else {
            console.log('no buffs while getting expendable resource: ' + resourceName);
         }
      }

      if (!resourceImages) {
         return; // return if buffs haven't been updated yet
      }

      var image = self._getExpendableResourceIndicatorImage(resourceName, resourceImages, resourcePercentage);
      self.set('health_status', statusLabel);
      self.set('model.health_indicator_style', 'background-image: url(' + image + ')');
      // TODO: play an animation when switching images
   }.observes('model.stonehearth:expendable_resources', 'model.stonehearth:buffs'),

   _getExpendableResourceIndicatorImage: function(name, images, percentage) {
      var constants = App.uiConstants.expendable_resources;
      var data = constants[name];
      var index = 0;

      if (percentage < 0) {
         percentage = 0;
      }

      if (percentage >= 0.99) {
         index = data.resource_full_index;
      } else if (percentage <= 0.1) {
         index = data.resource_empty_index;
      } else {
         index = Math.ceil(percentage * data.max_sections);
      }

      return images[index];
   },

   //Call on a jquery object (usually a div) whose ID matches the name of the attribute
   _showBuffEffects: function(obj, buffsByAttribute, attributeName) {
      var attributeValue = this.get('model.stonehearth:attributes.attributes.' + attributeName + '.value');
      var attributeRoundedValue = this.get('model.stonehearth:attributes.attributes.' + attributeName + '.user_visible_value');

      // change colors of attributes
      if (attributeRoundedValue > attributeValue) {
         //If buff, make text green
         $(obj).removeClass('debuffedValue normalValue').addClass('buffedValue');
      } else if (attributeRoundedValue < attributeValue) {
         //If debuff, make text yellow
         $(obj).removeClass('buffedValue normalValue').addClass('debuffedValue');
      } else if (attributeRoundedValue == attributeValue) {
         //If nothing, keep steady
         $(obj).removeClass('debuffedValue buffedValue').addClass('normalValue');
      }
   },

   _showAttributeTooltip: function(obj, buffsByAttribute, attributeName) {
      // create tooltip
      var hasTooltip = App.tooltipHelper.hasTooltip(attributeName);
      if (hasTooltip) {
         App.tooltipHelper.createDynamicTooltip($(obj), function () {
            //For each buff and debuff that's associated with this attribute,
            //put it in the tooltip
            if (buffsByAttribute[attributeName] != null) {
               var buffString = '<div class="buffTooltip">';
               for (var i = 0; i < buffsByAttribute[attributeName].length; i++) {
                  var buff = buffsByAttribute[attributeName][i]
                  buffString += `<span class="buffTooltipText"><span class="dataSpan ${buff.class}">${i18n.t(buff.shortDescription)}</span>`
                              + `<img class="buffTooltipImg" src="${buff.icon}"> ${i18n.t(buff.display_name)}</span></br>`;
               }
               buffString = buffString + '</div>';
            }

            return $(App.tooltipHelper.getTooltip(attributeName, buffString, false));
         });
      }
   },

   // ACE: take stacks into account
   _sortBuffsByAttribute: function() {
      var allBuffs = this.get('model.stonehearth:buffs.buffs');
      var buffsByAttribute = {};
      if (allBuffs) {
         radiant.each(allBuffs, function(_, buff) {
            //If the buff is private don't add it. Public buffs can be undefined or is_private = false
            if (buff.invisible_to_player == undefined || !buff.invisible_to_player) {
               var modifiers = buff.modifiers;
               for (var mod in modifiers) {
                  var new_buff_data = {}
                  new_buff_data.display_name = buff.display_name;
                  new_buff_data.axis = buff.axis;
                  new_buff_data.icon = buff.icon;
                  new_buff_data.shortDescription = '';
                  if (buff.short_description != undefined) {
                     new_buff_data.shortDescription = buff.short_description;
                  } else {
                     for (var attrib in modifiers[mod]) {
                        if (attrib == 'multiply' || attrib == 'divide') {
                           var number = Math.pow(modifiers[mod][attrib], buff.stacks);
                           if (attrib == 'divide') {
                              number = 1 / number;
                           }
                           var rounded = Math.round( (number - 1) * 1000 ) / 10;
                           new_buff_data.class = rounded >= 0 ? 'buffDataSpan' : 'debuffDataSpan';
                           new_buff_data.shortDescription += (rounded >= 0 ? '+' : '-') + Math.abs(rounded) + '% ';
                        } else if (attrib == 'add') {
                           var number = modifiers[mod][attrib] * buff.stacks;
                           if (number < 0) {
                              new_buff_data.shortDescription += number + ' ';
                              new_buff_data.class = 'debuffDataSpan';
                           } else {
                              new_buff_data.shortDescription += '+' + number + ' ';
                              new_buff_data.class = 'buffDataSpan';
                           }
                        }
                     }
                  }
                  //There are so many ways to modify a buff; let writer pick string
                  if (buffsByAttribute[mod] == null) {
                     buffsByAttribute[mod] = [];
                  }
                  buffsByAttribute[mod].push(new_buff_data);
               }
            }
         });
      }
      return buffsByAttribute;
   },

   _updateMorale: function() {
      if (!this.get('uri')) return;
      
      var self = this;
      var scoresToUpdate = ['happiness', 'food', 'shelter', 'safety'];
      radiant.each(scoresToUpdate, function(i, score_name) {
         var score_value = self.get('model.stonehearth:score.scores.' + score_name + '.score');
         self.set('score_' + score_name, Math.floor(score_value) / 10);
      });
   }.observes('model.stonehearth:score'),

   _updateBackpackItems : function() {
      if (!this.get('uri')) return;
      
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         if (!self._backpackItemsPalette) {
            // When moving a crate, this function will fire, but no UI will be present.  For now, be lazy
            // and just ignore this case.
            return;
         }
         var tracker = self.get('model.stonehearth:storage.item_tracker');
         self._backpackItemsPalette.stonehearthItemPalette('updateItems', tracker.tracking_data);
      });
   }.observes('model.stonehearth:storage.item_tracker'),

   willDestroyElement: function() {
      if (this._backpackItemsPalette) {
         this._backpackItemsPalette.stonehearthItemPalette('destroy');
         this._backpackItemsPalette = null;
      }

      $(top).off('radiant_selection_changed.citizen_character_sheet');

      this._nameInput.destroy();

      this.$().find('.tooltipstered').tooltipster('destroy');

      this._super();
   },

   didInsertElement: function() {
      var self = this;

      this.$().draggable({ handle: '.title'});

      App.tooltipHelper.createDynamicTooltip($('#expStat .bar'));
      App.tooltipHelper.createDynamicTooltip($('#healthDisplay'));

      var p = this.get('model.stonehearth:personality');
      var b = this.get('model.stonehearth:buffs');

      // have the character sheet tract the selected entity.
      $(top).on('radiant_selection_changed.citizen_character_sheet', function (_, data) {
         self._onEntitySelected(data);
      });

      self._nameInput = new StonehearthInputHelper(self.$('#name'), function (value) {
         // Ignore name input if player does not own the entity
         if (radiant.isOwnedByAnotherPlayer(self.get('model'), App.stonehearthClient.getPlayerId())) {
            self.$('#name').val(self.get('model.unit_name'));
            return;
         }

         radiant.call('stonehearth:set_custom_name', self.uri, value, false); // false for skip setting custom name
      });

      if (p) {
         $('#personality').html($.t(p.personality));
      }
      if (b) {
         self._updateAttributes();
      }

      this._backpackItemsPalette = this.$('#backpackItemsPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
      });
      this._segmentsInitialized = false;
		
      self.$('#description').click(function () {
         if (self.get('uri')) {
            if (radiant.isOwnedByAnotherPlayer(self.get('model'), App.stonehearthClient.getPlayerId())) {
               return;
            }
            App.stonehearthClient.showPromotionTree(self.get('uri'), self.get('model.stonehearth:job.job_index'));
         }
      });

      App.tooltipHelper.createDynamicTooltip(self.$('#teleportButton'), function () {
         var isDisabled = self.get('teleport_disabled');
         var ownedByAnotherPlayer = false;
         if (self.get('model')) {
            ownedByAnotherPlayer = radiant.isOwnedByAnotherPlayer(self.get('model'), App.stonehearthClient.getPlayerId());
         }
         if (ownedByAnotherPlayer) {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.teleport.different_player_description');
         } else if (isDisabled && self.get('on_teleport_cooldown')) {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.teleport.disabled_description');
         } else if (isDisabled && self.get('not_idle')) {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.teleport.not_idle_description');
         } else {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.teleport.description');
         }
      });

      self.$('#name').focus(function() {
         self.$('#name').val(self.get('model.custom_name'))
            .select();
      })
      .blur(function() {
         // if the name didn't change, make sure we add back any title we might have!
         // (if the name did change, this will get taken care of automatically by the _onNameChanged function)
         if (self.$('#name').val() == self.get('model.custom_name')) {
            self.$('#name').val(self.get('model.unit_name'));
         }
      })
      .on('mousedown', function(e) {
         if (e.button == 2) {
            self._showTitleSelectionList();
            e.preventDefault();
         }
      });

      self.$('#lockTitle').click(function() {
         // toggle title lock for this entity
         radiant.call('stonehearth_ace:lock_title', self.get('uri'), !self.get('model.stonehearth:unit_info.title_locked'))
      });

      App.tooltipHelper.createDynamicTooltip(self.$('#lockTitle'), function () {
         var locked = self.get('model.stonehearth:unit_info.title_locked');
         if (locked == null) {
            return;
         }

         var sLocked = locked ? 'unlock' : 'lock';
         return $(App.tooltipHelper.createTooltip(i18n.t(`stonehearth_ace:ui.game.unit_frame.${sLocked}_title.title`),
               i18n.t(`stonehearth_ace:ui.game.unit_frame.${sLocked}_title.description`)));
      });
   },

   _showTitleSelectionList: function(e) {
      var self = this;

      // make sure they don't have title locked
      if (self.get('model.stonehearth:unit_info.title_locked')) {
         return;
      }

      var result = stonehearth_ace.createTitleSelectionList(self._titles, self.get('model.stonehearth_ace:titles.titles'), self.get('uri'), self.get('model.custom_name'));
      if (result) {
         self.$('#name').after(result.container);
         result.showList();
      }
   },

   _loadAvailableTitles: function() {
      // when the selection changes, load up the appropriate titles json
      var self = this;
      self._titles = {};
      var json = self.get('model.stonehearth_ace:titles.titles_json');
      if (json) {
         stonehearth_ace.loadAvailableTitles(json, function(data){
            self._titles = data;
         });
      }
   }.observes('model.uri'),

   _onTeleportEnabled: function() {
      if (!this.get('uri')) return;
      
      var ownedByAnotherPlayer = radiant.isOwnedByAnotherPlayer(this.get('model'), App.stonehearthClient.getPlayerId());
      var isDisabled = !this.get('model.stonehearth:teleportation.enabled') || ownedByAnotherPlayer;
      this.set('teleport_disabled', isDisabled);
      this.set('not_idle', !this.get('model.stonehearth:teleportation.idling'));
      this.set('on_teleport_cooldown', this.get('model.stonehearth:teleportation.on_cooldown'));
   }.observes('model.stonehearth:teleportation'),

   // ACE: handle custom names with titles
   _onNameChanged: function() {
      var self = this;
      var unit_info = self.get('model.stonehearth:unit_info');
      var unit_name = i18n.t(unit_info && unit_info.display_name, {self: self.get('model')});
      var custom_name = unit_info && unit_info.custom_name;
      var title_description = unit_info && unit_info.current_title && unit_info.current_title.description;
      self.set('model.unit_name', unit_name);
      self.set('model.custom_name', custom_name);

      var text = title_description;
      var title;
      if (text) {
         text = i18n.t(text);
         title = unit_name;
      }
      else {
         text = unit_name;
      }

      var titleLockClass = null;
      // first check if titles are even an option for this entity
      if (unit_info && self.get('model.stonehearth_ace:titles')) {
         titleLockClass = unit_info.title_locked ? 'locked' : 'unlocked';
      }
      self.set('titleLockClass', titleLockClass);
      self.notifyPropertyChange('titleLockClass');

      App.guiHelper.addTooltip(self.$('#name'), text, title || "");
   }.observes('model.stonehearth:unit_info'),

   _onEntitySelected: function(e) {
      var self = this;
      if (!self.get('uri')) {
         return;
      }

      var entity = e.selected_entity

      if (!entity || App.stonehearthClient.getPlayerId() != e.player_id) {
         self.dismiss();
         return;
      }

      // nuke the old trace
      if (self.selectedEntityTrace) {
         self.selectedEntityTrace.destroy();
      }

      // trace the properties so we can tell if we need to popup the properties window for the object
      self.selectedEntityTrace = new StonehearthDataTrace(entity)
         .progress(function(result) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self._examineEntity(result);
         })
         .fail(function(e) {
            console.log(e);
         });
   },

   _examineEntity: function(entity) {
      var self = this;

      if (!entity) {
         self.dismiss();
         return;
      }

      var alias = entity.get('uri');
      var catalogData = App.catalog.getCatalogData(alias);

      var materials = "";
      if (catalogData) {
         if ((typeof catalogData.materials) === 'string') {
            materials = catalogData.materials.split(' ');
         } else {
            materials = catalogData.materials;
         }
      }
      if (materials && materials.indexOf('human') >= 0) {
         self.set('uri', entity.__self);
         self._resetVars();
      } else  {
         self.dismiss();
      }
      self._segmentsInitialized = false;
   },

   _resetVars: function() {
      var self = this;
      self._currentPressure = null;
      self._currentHappiness = null;
      self._currentMood = null;
      self.set('morale_arrow_style', 'display: none'); // hide morale arrow when switching to another entity to prevent transition animation
   },

   destroy: function() {
      if (this.selectedEntityTrace) {
         this.selectedEntityTrace.destroy();
      }
      if (this._jobPerkTrace) {
         this._jobPerkTrace.destroy();
         this._jobPerkTrace = null;
      }

      App.stonehearth.citizenCharacterSheetView = null;

      this._super();
   },

   /*************  Appeal Tab UI  ****************/

   _initializeAppealTooltips: function () {
      var self = this;

      if (!self.get('model') || !self.$('[tabPage="appealTab"]')) {
         return;
      }

      App.tooltipHelper.createDynamicTooltip(self.$('.appeal-bar-title'), function () {
         return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.current_and_target_bar_tooltip', { self: self.get('model') });
      });
      App.tooltipHelper.createDynamicTooltip(self.$('.arrow.target'), function () {
         return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.target_arrow_tooltip', { self: self.get('model') });
      });
      App.tooltipHelper.createDynamicTooltip(self.$('.arrow.current'), function () {
         return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.current_arrow_tooltip', { self: self.get('model') });
      });

      self.$('[tabPage="appealTab"]').click(function () {
         if (self.get('model.stonehearth:appeal.item_discovery_unseen_flag')) {
            radiant.call_obj(self.get('model.stonehearth:appeal'), 'mark_item_preferences_seen_command');
         }
      });
   }.observes('model'),

   _initializeAppealThoughtThresholds: function () {
      var self = this;

      // Format the thresholds.
      var thresholds = radiant.deep_copy_pod(App.constants.appeal.LEVELS);
      _.each(thresholds, function (value, key) {
         value.name = i18n.t(value.ui_label);
         value.sentiment = value.positive != null ? (value.positive ? 'positive' : 'negative') : 'neutral';
      });

      // Set the minimum of each step to the maximum of the previous step.
      thresholds[0].min = App.constants.appeal.DISPLAY_RANGE[0];
      for (var i = 1; i < thresholds.length; ++i) {
         thresholds[i].min = thresholds[i - 1].max;
      }
      
      // Position and tooltipify the bar sections.
      Ember.run.scheduleOnce('afterRender', this, function () {
         if (!self.$('#appealBar')) return;
         self.$('#appealBar').css('width', self.APPEAL_BAR_WIDTH);
         self.$('#appealBar .barSection').each(function () {
            $(this).css('left', self._appealToBarPosition($(this).attr('data-min')));
            $(this).css('right', self.APPEAL_BAR_WIDTH - self._appealToBarPosition($(this).attr('data-max')));
            App.tooltipHelper.createDynamicTooltip($(this));
         });
      });

      self.set('appealThoughtThresholds', thresholds);
   }.observes('model'),

   _updateItemPreferences: function () {
      if (!this.get('uri')) return;
      
      var self = this;

      if (!self.get('model.stonehearth:appeal.item_preferences')) {
         return;  // No data yet.
      }

      var itemPreferences = {};
      var discovered = self.get('model.stonehearth:appeal.item_discovered_flags');
      self.set('itemPreferenceTitle', i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.item_preferences', { self: this.get('model') }));
      _.each(self.get('model.stonehearth:appeal.item_preferences'), function (value, key) {
         var catalogData = App.catalog.getCatalogData(key);
         itemPreferences[value] = itemPreferences[value] || { items: [] };
         itemPreferences[value].sentimentTitle = i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.' + value);
         itemPreferences[value].sentimentClass = 'sentiment-' + value
         itemPreferences[value].items.push({
            uri: key,
            name: i18n.t(catalogData ? catalogData.display_name : key),
            icon: catalogData?catalogData.icon:"",
            sentiment: value == 'love' ? 2 : (value == 'like' ? 1 : 0),
            discovered: Boolean(discovered[key])
         });
      });

      // Sort each section by discovery and URI (for consistency).
      _.each(itemPreferences, function (category, key) {
         category.items.sort(function (a, b) {
            if (a.discovered != b.discovered) {
               return a.discovered ? -1 : 1;
            } else {
               if (a.uri > b.uri) {
                  return -1;
               } else if (a.uri < b.uri) {
                  return 1;
               } else {
                  return 0;
               }
            }
         });
      });

      // Convert the categories into a list.
      itemPreferences = [itemPreferences['love'], itemPreferences['like'], itemPreferences['dislike']];

      if (self.get('itemPreferences') && _.isEqual(self.get('itemPreferences'), itemPreferences)) {
         return;  // No change. Don't re-render so tooltips aren't invalidated.
      }

      // Tooltipify each item when the results are rendered.
      Ember.run.scheduleOnce('afterRender', this, function () {
         if (!self.$()) return;
         App.tooltipHelper.createDynamicTooltip(self.$('.sentiment-title.sentiment-like'), function() {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.like_tooltip', { self: self.get('model') });
         });
         App.tooltipHelper.createDynamicTooltip(self.$('.sentiment-title.sentiment-love'), function() {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.love_tooltip', { self: self.get('model') });
         });
         App.tooltipHelper.createDynamicTooltip(self.$('.sentiment-title.sentiment-dislike'), function() {
            return i18n.t('stonehearth:ui.game.citizen_character_sheet.appeal_headings.dislike_tooltip', { self: self.get('model') });
         });
         self.$('#itemPreferences .item').each(function () {
            var item = $(this);
            App.tooltipHelper.createDynamicTooltip(item, function () {
               return $('.icon', item).attr('title');
            });
         });
      });

      self.set('itemPreferences', itemPreferences);
   }.observes('model.stonehearth:appeal', 'model.stonehearth:unit_info'),

   _updateAppealArrows: function () {
      if (!this.get('uri') || !this.$('.appealArrows')) {
         return;
      }

      var self = this;
      self.$('.appealArrows .arrow.current').css('left', self._appealToBarPosition(self.get('model.stonehearth:appeal.effective_appeal')));
      self.$('.appealArrows .arrow.current .value').text(self.get('model.stonehearth:appeal.effective_appeal').toFixed(1));
      self.$('.appealArrows .arrow.target').css('left', self._appealToBarPosition(self.get('model.stonehearth:appeal.last_sample')));
      self.$('.appealArrows .arrow.target .value').text(self.get('model.stonehearth:appeal.last_sample').toFixed(1));
   }.observes('model.stonehearth:appeal'),

   _appealToBarPosition: function (value) {
      var self = this;
      var range = App.constants.appeal.DISPLAY_RANGE;
      var ratio = (value - range[0]) / (range[1] - range[0]);
      return Math.max(0, Math.min(ratio, 1)) * self.APPEAL_BAR_WIDTH;
   },


   actions: {
      doTeleport: function(isDisabled) {
         var command = {
            enabled: !isDisabled,
            action: "call",
            function: "stonehearth:teleport_hearthling"
         };

         App.stonehearthClient.doCommand(this.get('uri'), App.stonehearthClient.getPlayerId(), command);
      }
   }
});
