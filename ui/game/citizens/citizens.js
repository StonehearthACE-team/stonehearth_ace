App.StonehearthCitizensView.reopen({
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

   actions: {
      showPromotionTree: function(citizen) {
         App.stonehearthClient.showPromotionTree(citizen.__self, citizen['stonehearth:job'].job_index);
      }
   }
});

App.StonehearthCitizenTasksRowView.reopen({
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
