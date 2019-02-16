App.StonehearthCitizenTasksRowView.reopen({
   didInsertElement: function() {
      this._super();
      var self = this;

      $(top).on('radiant_selection_changed.unit_frame', function (_, e) {
         self._onEntitySelected(e);
      });
   },

   _onEntitySelected: function(e) {
      var self = this;
      if (e.selected_entity == self._uri) {
         self._selectRow(false);
      }
   },

   willDestroyElement: function() {
      var self = this;
      $(top).off('radiant_selection_changed.unit_frame');
      self._super();
   }
});
