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
