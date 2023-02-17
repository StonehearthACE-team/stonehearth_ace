App.StonehearthDeliveryQuestBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'deliveryQuestBulletinDialog',

   SHOULD_DESTROY_ON_HIDE_DIALOG: true,

   init: function () {
      this._super();
      var self = this;

      self._traces = [];
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self._wireButtonToCallback('#completeButton', 'on_try_complete', true);
      self._wireButtonToCallback('#abandonButton', 'on_abandon', true);
   },

   destroy: function() {
      var self = this;
      
      _.each(self._traces, function(t) {
         t.destroy();
      });
      self._traces = [];
      
      App.jobController.removeChangeCallback('delivery_quest_bulletin');

      this._super();
   },

   _startTraces: function () {
      var self = this;
      if (!self.get('model.data.requirements')) {
         return;  // Not ready yet.
      } else if (self._traces.length > 0) {
         return;  // Already set.
      }

      var reqTypes = {};
      radiant.each(self.get('model.data.requirements'), function (_, req) {
         var type = req.type == 'gold' ? ('gold_' + req.subtype) : req.type;
         reqTypes[type] = true;
      });

      if (reqTypes.give_item) self._traceItems('stonehearth:sellable_item_tracker', 'give_item', 'uri', 'itemCounts');
      if (reqTypes.give_material) self._traceItems('stonehearth:resource_material_tracker', 'give_material', 'material', 'materialCounts');
      if (reqTypes.job_level) self._traceJobs();
      if (reqTypes.happiness) self._traceHappiness();
      if (reqTypes.gold_have || reqTypes.gold_give) self._traceGold();
      if (reqTypes.gold_earned || reqTypes.gold_spent) self._traceTradeStats();
      if (reqTypes.have_item_quality) self._traceItemQualities();
      if (reqTypes.net_worth) self._traceNetWorth();
      if (reqTypes.placed_item) self._traceItems('stonehearth:basic_inventory_tracker', 'placed_item', 'uri', 'placedItemCounts');
   }.observes('model.data.requirements'),

   _recalculateRequirements: function() {
      var self = this;
      if (!self.get('model.data.requirements')) {
         return;  // Not ready yet.
      }

      var requirementsArray = [];
      _.each(self.get('model.data.requirements'), function (v, k) {
         var formatted = {};
         if (v.type == 'give_item') {
            var catalogData = App.catalog.getCatalogData(v.uri);
            formatted.count = v.count;
            formatted.display_name = catalogData.display_name;
            var materials = catalogData.materials;
            var isHealingItem = ((typeof materials) == 'string') ? materials.match(/\bhealing_item\b/) : materials.contains('healing_item');
            if (isHealingItem) {
               formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/healing.png';
            } else {
               formatted.icon = catalogData.icon;
            }
            formatted.available_count = (self.get('itemCounts') || {})[v.uri] || 0;
            formatted.fulfilled = formatted.available_count >= v.count;
         } else if (v.type == 'give_material') {
            var catalogData = App.resourceConstants.resources[v.material];
            formatted.count = v.count;
            formatted.display_name = catalogData.name;
            if (v.material == 'prepared_food') {
               formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/food.png';
            } else {
               formatted.icon = catalogData.icon;
            }
            formatted.available_count = (self.get('materialCounts') || {})[v.material] || 0;
            formatted.fulfilled = formatted.available_count >= v.count;
         } else if (v.type == 'job_level') {
            var prefix = i18n.t('stonehearth:ui.game.citizen_character_sheet.level_abbreviation') + ' ';
            formatted.count = prefix + v.level;
            var jobData = App.jobConstants[v.uri];
            if (jobData) {  // Mod classes may not have the job registered correctly.
               formatted.display_name = jobData.description.display_name;
               var roles = jobData.description.roles;
               var isCombatRole = ((typeof roles) === 'string' && roles.match(/\bcombat\b/)) || roles['combat'] != null;
               if (isCombatRole) {
                  formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/combat.png';
               } else {
                  formatted.icon = jobData.description.icon;
               }
            } else {
               formatted.display_name = v.uri + ' (unregistered job)';
            }
            var highestJobLevel = (self.get('jobLevels') || {})[v.uri] || 0;
            formatted.available_count = highestJobLevel ? (prefix + highestJobLevel) : '-';
            formatted.fulfilled = highestJobLevel >= v.level;
         } else if (v.type == 'happiness') {
            var required = v.min_citizens;
            formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/happiness.png';
            var moodName = "jubilant";
            for (var i = App.happinessConstants.moods.length - 1; i >= 0; --i) {
               var data = App.happinessConstants.mood_data[App.happinessConstants.moods[i]];
               if (data.max_threshold && v.min_value >= data.max_threshold) {
                  moodName = App.happinessConstants.moods[i+1];
                  break;
               }
            }
            var moodNameLocalized = i18n.t('stonehearth:ui.data.tooltips.' + moodName + '.display_name');
            if (v.min_citizens == 'all') {
               required = App.population.getPopulationData().citizens.size;
               formatted.count = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.happiness_requirement_all', {value: required});
               formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.happiness_requirement_label_all', { moodName: moodNameLocalized });
            } else {
               formatted.count = v.min_citizens;
               formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.happiness_requirement_label', { value: v.min_citizens, moodName: moodNameLocalized });
            }
            formatted.available_count = '?';
            if (self.get('citizensHappiness')) {
               var numFulfilled = 0;
               radiant.each(self.get('citizensHappiness'), function (_, happiness) {
                  if (happiness >= v.min_value) {
                     numFulfilled++;
                  }
               });
               formatted.available_count = numFulfilled;
            }
            formatted.fulfilled = formatted.available_count >= required;
         } else if (v.type == 'gold') {
            formatted.count = v.count;
            formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.gold_label.' + v.subtype);
            formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/gold.png';
            if (v.subtype == 'give' || v.subtype == 'have') {
               formatted.available_count = self.get('goldOnHand') || 0;
            } else {
               formatted.available_count = (self.get('tradeStats') || {})[v.subtype] || 0;
            }
            formatted.fulfilled = formatted.available_count >= v.count;
         } else if (v.type == 'have_item_quality') {
            formatted.count = v.count;
            formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.quality_label.quality_' + v.quality);
            formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/quality.png';

            var available = 0;
            radiant.each(self.get('itemQualityCounts'), function(quality, count) {
               if (quality >= v.quality) {
                  available += count;
               }
            });
            formatted.available_count = available;

            formatted.fulfilled = formatted.available_count >= v.count;
         } else if (v.type == 'net_worth') {
            formatted.count = v.value;
            formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.net_worth_label');
            formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/gold.png';
            formatted.available_count = self.get('netWorth') || 0;
            formatted.fulfilled = formatted.available_count >= v.value;
         } else if (v.type == 'placed_item') {
            formatted.count = v.count || 1;
            formatted.display_name = i18n.t('stonehearth:ui.game.bulletin.delivery_quest.placed_item_label', { itemName: App.catalog.getCatalogData(v.uri).display_name });
            formatted.icon = '/stonehearth/ui/game/bulletin/bulletin_dialog/delivery_quest_dialog/images/placed.png';
            formatted.available_count = (self.get('placedItemCounts') || {})[v.uri] || 0;
            formatted.fulfilled = formatted.available_count >= v.count || 1;
         }
         requirementsArray.push(formatted);
      });
      self.set('requirements', requirementsArray);
   }.observes('model.data.requirements', 'itemCounts', 'materialCounts', 'jobLevels', 'citizensHappiness', 'goldOnHand', 'tradeStats', 'itemQualityCounts'),

   _traceItems: function (tracker, req_type, req_key, property) {
      var self = this;
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', tracker)
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var traceFields = { 'tracking_data': {} };
            _.each(self.get('model.data.requirements'), function (v, k) {
               if (v.type == req_type) {
                  traceFields[v[req_key]] = { 'count': {} };
               }
            });
            if (_.isEmpty(traceFields)) {
               // Don't try to trace all the things.
               self._callCallback('on_recalculate_requirements');
               self.set(property, {});
            } else {
               self._traces.push(new StonehearthDataTrace(response.tracker, traceFields)
                  .progress(function (response) {
                     if (self.isDestroying || self.isDestroyed) {
                        return;
                     }
                     var counts = {};
                     radiant.each(response.tracking_data, function (key, entry) {
                        counts[key] = entry.count;
                     });
                     self.set(property, counts);
                     self._callCallback('on_recalculate_requirements');
                  }));
            }
         });
   },

   _traceJobs: function () {
      var self = this;

      App.jobController.addChangeCallback('delivery_quest_bulletin', function() {
         var jobLevels = {};
         _.each(App.jobController.getJobControllerData().jobs, function(data, uri) {
            jobLevels[uri] = data.highest_level;
         });
         self.set('jobLevels', jobLevels);
         self._callCallback('on_recalculate_requirements');
      }, true);
   },

   _traceHappiness: function () {
      var self = this;
      
      radiant.call('stonehearth:get_population')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var traceFields = {
               "citizens": {
                  "*": {
                     "stonehearth:happiness": {},
                  }
               }
            };
            self._traces.push(new StonehearthDataTrace(response.population, traceFields)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var happiness = {};
                  delete response.citizens.size;
                  radiant.each(response.citizens, function (key, citizen) {
                     happiness[key] = citizen['stonehearth:happiness'].current_happiness;
                  });
                  self.set('citizensHappiness', happiness);
                  self._callCallback('on_recalculate_requirements');
               }));
         });
   },

   _traceGold: function () {
      var self = this;
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:basic_inventory_tracker')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var traceFields = {
               "tracking_data": {
                  "stonehearth:loot:gold": {
                     "items": {
                        "*": {
                           "stonehearth:stacks": {}
                        }
                     }
                  }
               }
            };
            self._traces.push(new StonehearthDataTrace(response.tracker, traceFields)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var count = 0;
                  radiant.each(response.tracking_data, function (key, entry) {
                     if (key == 'stonehearth:loot:gold') {
                        radiant.each(entry.items, function (_, item) {
                           count += item['stonehearth:stacks'].stacks;
                        });
                     }
                  });
                  self.set('goldOnHand', count);
                  self._callCallback('on_recalculate_requirements');
               }));
         });
   },

   _traceTradeStats: function () {
      var self = this;

      radiant.call_obj('stonehearth.inventory', 'get_inventory_command')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var traceFields = {
               "trade_stats": {}
            };
            self._traces.push(new StonehearthDataTrace(response.result, traceFields)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  self.set('tradeStats', response.trade_stats);
                  self._callCallback('on_recalculate_requirements');
               }));
         });
   },

   _traceItemQualities: function () {
      var self = this;
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:basic_inventory_tracker')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            var traceFields = { 'tracking_data': { '*': { 'item_qualities': { '*': {} } } } };
            self._traces.push(new StonehearthDataTrace(response.tracker, traceFields)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var counts = {};
                  radiant.each(response.tracking_data, function (_, entry) {
                     radiant.each(entry.item_qualities, function (_, item_quality_entry) {
                        counts[item_quality_entry.item_quality] = (counts[item_quality_entry.item_quality] || 0) + item_quality_entry.count;
                     });
                  });
                  self.set('itemQualityCounts', counts);
                  self._callCallback('on_recalculate_requirements');
               }));
         });
   },

   _traceNetWorth: function () {
      var self = this;
      self._traces.push(new StonehearthDataTrace(App.stonehearthClient.gameState.scoresUri, {})
         .progress(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }
            self.set('netWorth', response.total_scores.net_worth);
            self._callCallback('on_recalculate_requirements');
         }));
   },

   // ACE: added for quest storage item tracking
   _updateFromI18nData: function() {
      var self = this;
      var i18n_data = self.get('model.i18n_data');
      var requirements = self.get('requirements');
      var rawReqData = self.get('model.data.requirements');
      if (!requirements || !rawReqData) return;

      // we have to match up any requirements listed in i18n_data with the overall requirements
      var id = 1;
      var i18n_reqs = [];
      while (true) {
         var data = i18n_data && i18n_data['req_' + id];
         if (!data) break;
         i18n_reqs.push(data);
         id++;
      }

      for (var i = 0; i < requirements.length; i++) {
         var requirement = rawReqData[i];
         var foundReq = false;
         for (var j = 0; j < i18n_reqs.length; j++) {
            var i18nData = i18n_reqs[j];
            var i18nReq = i18nData.requirement;
            if ((requirement.type == 'give_item' && !requirement.keep_items && i18nReq.uri == requirement.uri) ||
                  (requirement.type == 'give_material' && !requirement.keep_items && i18nReq.material == requirement.material)) {
               Ember.set(requirements[i], 'real_available_count', requirements[i].available_count + (i18nData.quantity || 0));
               Ember.set(requirements[i], 'items_cached_class', i18nData.items_cached_class || 'noCache');
               Ember.set(requirements[i], 'cached_count', i18nData.quantity && ` <span class='numCached'>(${i18nData.quantity})</span>` || '');
               Ember.set(requirements[i], 'fulfilled', requirements[i].real_available_count >= requirement.count);
               foundReq = true;
               break;
            }
         }
         
         if (!foundReq) {
            Ember.set(requirements[i], 'real_available_count', requirements[i].available_count);
            Ember.set(requirements[i], 'items_cached_class', '');
            Ember.set(requirements[i], 'cached_count', '');
            Ember.set(requirements[i], 'fulfilled', requirements[i].real_available_count >= requirements[i].count);
         }
      }
   }.observes('model.i18n_data', 'requirements'),
});
