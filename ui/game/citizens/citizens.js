var getOctile = function(percentage) {
   // return 0-8
   return Math.round(percentage * 8);
};

App.StonehearthCitizensView.reopen({
   ace_components: {
      "citizens" : {
         "*": {
            'stonehearth:expendable_resources' : {},
            'stonehearth:incapacitation' : {
               'sm': {}
            },
         }
      }
   },

   init: function() {
      var self = this;
      stonehearth_ace.mergeInto(self.components, self.ace_components)

      self._super();
   },

   didInsertElement: function() {
      var self = this;
      self._firstTime = true;
      self._super();
   },

   _onVisibilityChanged: function() {
      var self = this;
      if (self._firstTime) {
         self._firstTime = null;
         return;
      }

      if (self.get('isVisible')) {
         // tell each row to update
         self._containerView.forEach(function(item, index, enumerable) {
            item.updateRow();
         });
      }
   }.observes('isVisible'),

   selected_commands: function() {
      var filter_fn = function(uri, data) {
         if (data.visible_in_citizens_view === false) {
            return false;
         }
      };
      var commands = radiant.map_to_array(this.get('selected.stonehearth:commands.commands'), filter_fn);
      commands.sort(function(a, b){
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      });
      return commands;
   }.property('selected.stonehearth:commands.commands'),

   actions: {
      showPromotionTree: function(citizen) {
         App.stonehearthClient.showPromotionTree(citizen.__self, citizen['stonehearth:job'].job_index);
      }
   }
});

App.StonehearthCitizenTasksRowView.reopen({
   ace_components: {
      'stonehearth:attributes' : {},
      'stonehearth:expendable_resources' : {},
      'stonehearth:incapacitation' : {
         'sm': {}
      },
   },

   init: function() {
      var self = this;
      stonehearth_ace.mergeInto(self.components, self.ace_components)

      self._super();
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      // use a specific function for this rather than a namespace, because we want it then remove the event just for this row
      self.selection_event_func = function(_, e) {
         self._onEntitySelected(e);
      }

      $(top).on('radiant_selection_changed', self.selection_event_func);
   },

   _onEntitySelected: function(e) {
      var self = this;
      if (e.selected_entity == self._uri) {
         self._selectRow(false);
      }
   },

   willDestroyElement: function() {
      var self = this;
      $(top).off('radiant_selection_changed', self.selection_event_func);
      self._super();
   },

   _updateHealth: function() {
      var self = this;
      var currentHealth = self.get('model.stonehearth:expendable_resources.resources.health');
      if (currentHealth == null) {
         return;
      }

      currentHealth = Math.ceil(currentHealth);
      var currentGuts = Math.ceil(self.get('model.stonehearth:expendable_resources.resources.guts'));
      var maxGuts = Math.ceil(self.get('model.stonehearth:attributes.attributes.max_guts.effective_value'));
      var percentGuts = currentGuts / maxGuts;

      var maxHealth = Math.ceil(self.get('model.stonehearth:attributes.attributes.max_health.effective_value'));
      var effMaxHealthPercent = Math.ceil(self.get('model.stonehearth:attributes.attributes.effective_max_health_percent.effective_value') || 100);
      var incapacitationState = self.get('model.stonehearth:incapacitation.sm.current_state');
      var percentHealth = currentHealth / maxHealth;
      var icon;
      var isWounded = effMaxHealthPercent != 100;
      
      if (currentHealth == 0) {
         // if health is 0, check guts:
         if (currentGuts == maxGuts) {
            icon = "heart_full"
         }
         else if (currentGuts > 0) {
            icon = `heart_${getOctile(percentGuts)}_8`;
         }
         else {
            icon = "heart_empty";
         }
      }
      else if (currentHealth == maxHealth) {
         icon = "heart_full"
      }
      else {
         icon = `heart_${getOctile(percentHealth)}_8`;
      }

      var value = percentGuts;
      if (incapacitationState == 'recuperating') {
         icon = "recuperating/" + icon;
      }
      else if (incapacitationState == 'normal') {
         if (isWounded) {
            icon = "wounded/" + icon;
         }
         value = percentHealth;
      }
      else {
         // dying/dead
         icon = "dying/" + icon;
      }

      icon = "/stonehearth_ace/ui/game/citizens/images/health/" + icon + ".png";

      var healthData = {
         icon: icon,
         value: value,
         incapacitationState: incapacitationState,
         isWounded: isWounded,
      };

      var curHealthData = self.get('healthData');

      if (!curHealthData || curHealthData.icon != healthData.icon || curHealthData.value != healthData.value) {
         self.set('healthData', healthData);

         Ember.run.scheduleOnce('afterRender', self, function() {
            var citizenData = self.get('model');
            if (citizenData) {
               App.tooltipHelper.createDynamicTooltip(self.$('.healthColumn'), function () {
                  if (!healthData) {
                     return;
                  }

                  var value = Math.floor(100 * healthData.value);
                  var tooltipKey;
                  if (incapacitationState == 'recuperating') {
                     tooltipKey = 'recuperating';
                  }
                  else if (incapacitationState == 'normal') {
                     tooltipKey = healthData.isWounded ? 'wounded' : (value == 100 ? 'healthy' : 'hurt');
                  }
                  else {
                     tooltipKey = 'dying';
                  }

                  var healthString = App.tooltipHelper.createTooltip(
                     i18n.t(`stonehearth_ace:ui.game.citizens.health_tooltips.${tooltipKey}_title`, {value: value}),
                     i18n.t(`stonehearth_ace:ui.game.citizens.health_tooltips.${tooltipKey}_description`, {value: value}));
                  return $(healthString);
               });
            }
         });
      }
   }.observes('model.uri', 'model.stonehearth:expendable_resources', 'model.stonehearth:attributes.attributes'),

   updateRow: function() {
      var self = this;

      self._update();
      self._onWorkingForChanged();
      self._updateMoodTooltip();
      self._updateDescriptionTooltip();
      self._onJobChanged();
   }
});

App.StonehearthCitizenTasksContainerView.reopen({
   _getCitizenRowsSortFn: function(citizensMap) {
      var self = this;
      // Sort based on the sorting property selected by player
      var sortDirection = self.containerParentView.get('sortDirection') || citizensLastSortDirection;
      var sortKey = self.containerParentView.get('sortKey') || citizensLastSortKey;
      var keyExtractors = {
         'job': function(x) {
            return self._getJobSortKey(x['stonehearth:job']);
         },
         'name': function(x) {
            return x['stonehearth:unit_info'] && i18n.t(x['stonehearth:unit_info'].custom_name, {self: x});
         },
         'activity': function(x) {
            return x['stonehearth:ai'] && i18n.t(x['stonehearth:ai'].status_text_key, {self: x});
         },
         'body': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.body.user_visible_value;
         },
         'mind': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.mind.user_visible_value;
         },
         'spirit': function(x) {
            return x['stonehearth:attributes'] && x['stonehearth:attributes'].attributes.spirit.user_visible_value;
         },
         'happiness': function(x) {
            return x['stonehearth:happiness'] && x['stonehearth:happiness'].current_happiness;
         },
         'health': function(x) {
            var incapacitationState = x['stonehearth:incapacitation'].sm.current_state;
            var currentGuts = Math.ceil(x['stonehearth:expendable_resources'].resources.health);
            var maxGuts = Math.ceil(x['stonehearth:attributes'].attributes.max_guts.user_visible_value);
            if (currentGuts < maxGuts) {
               return currentGuts / maxGuts + (incapacitationState == 'recuperating' ? 2 : 0);
            }
            var currentHealth = Math.ceil(x['stonehearth:expendable_resources'].resources.health);
            var maxHealth = Math.ceil(x['stonehearth:attributes'].attributes.max_health.user_visible_value);
            var effMaxHealthPercent = Math.ceil(x['stonehearth:attributes'].attributes.effective_max_health_percent.user_visible_value || 100);
            return currentHealth / maxHealth + (effMaxHealthPercent != 100 && 6 || 4);
         },
         'working-for': function(x) {
            return x['stonehearth:work_order'] && i18n.t(x['stonehearth:work_order'].working_for);
         },
         'haul-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.haul && x['stonehearth:work_order'].work_order_statuses.haul != 'disabled') ? 1 : 0;
         },
         'build-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.build && x['stonehearth:work_order'].work_order_statuses.build != 'disabled') ? 1 : 0;
         },
         'mine-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.mine && x['stonehearth:work_order'].work_order_statuses.mine != 'disabled') ? 1 : 0;
         },
         'job-enabled': function(x) {
            return x['stonehearth:work_order'] && (x['stonehearth:work_order'].work_order_refs.job && x['stonehearth:work_order'].work_order_statuses.job != 'disabled') ? 1 : 0;
         },
      };

      return function(aCitizenId, bCitizenId) {
         if (!aCitizenId || !bCitizenId) {
            return 0;
         }

         var aModel = self.currentCitizensMap[aCitizenId];
         var bModel = self.currentCitizensMap[bCitizenId];

         if (!aModel || !bModel) {
            return 0;
         }
         var aKey = keyExtractors[sortKey](aModel);
         var bKey = keyExtractors[sortKey](bModel);
         var n = (typeof aKey == 'string') ? aKey.localeCompare(bKey) : (aKey < bKey ? -1 : (aKey > bKey) ? 1 : 0);
         if (n == 0) {
            var aName = keyExtractors['name'](aModel);
            var bName = keyExtractors['name'](bModel);
            n = aName ? aName.localeCompare(bName) : 0;
         }

         return n * sortDirection;
      };
   },

   _getJobSortKey: function(job) {
      if (job) {
         var alias = job.job_uri;
         var isCombat = App.jobController.jobIsCombat(alias);
         var isCrafter = App.jobController.jobIsCrafter(alias);
         var localized = i18n.t(job.curr_job_name);

         return (isCombat ? '|combat|' : '') + (isCrafter ? '|crafter|' : '') + localized;
      }
   },
});
