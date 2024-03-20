App.StonehearthBuildingRoofToolContextView = App.View.extend({
   templateName: 'roofToolContext',
   toolContext: 'stonehearth:build2:entities:roof_widget',
   uriProperty: 'model',

   init: function() {
      var self = this;
      self._roofTrace = null;
      self._super();
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      radiant.call('stonehearth_ace:get_roof_tool_options')
         .done(function(response) {
            self.$('#dropWalls').prop('checked', response.drop_walls);
            self.$('#front').prop('checked', response.gradient.front);
            self.$('#back').prop('checked', response.gradient.back);
            self.$('#left').prop('checked', response.gradient.left);
            self.$('#right').prop('checked', response.gradient.right);
         });

      self.$(':checkbox').on('click', function(event) {
         // Prevent any checking; let the data from the server dictate our results.
         event.stopPropagation();

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_checkbox'});
         if (!self.get('uri') || !self.get('model')) {
            // no roof, so manually update the roof options
            self._setRoofOptions();
         }
         else {
            if ($(this).attr('id') == 'dropWalls') {
               self._applyDropWalls($(this).is(':checked'));
            } else {
               self._toggleGradient($(this).attr('id'), $(this).is(':checked'));
            }

            // if we're updating a selected tool, this will pass through from the trace
            // so return false here to prevent the checkbox from updating directly from this click
            event.preventDefault();
            return false;
         }
      });
   },

   show: function() {
      var self = this;
      self._super();
      self._setRoofOptions();
   },

   _setRoofOptions: function() {
      var self = this;
      var options = {
         drop_walls: self.$('#dropWalls').is(':checked'),
         gradient: {
            front: self.$('#front').is(':checked'),
            back: self.$('#back').is(':checked'),
            left: self.$('#left').is(':checked'),
            right: self.$('#right').is(':checked')
         }
      };
      radiant.call('stonehearth_ace:set_roof_tool_options', options);
   },

   _onSelectionChange: function() {
      var self = this;

      if (self._roofTrace) {
         self._roofTrace.destroy();
      }
      var roof = self.get('uri') && self.get('model');

      if (!roof) {
         return;
      }
      var roof_widget_uri = roof['stonehearth:build2:roof_widget'];

      self._roofTrace = new RadiantTrace();
      self._roofTrace.traceUri(roof_widget_uri).progress(function(result) {
         var roof_data;
         if (result.__fields) {  // If using SV tables, the data is stored under __fields.
            roof_data = result.__fields.data;
         } else {
            roof_data = result.data;
         }
         self._updateFromSelection(roof_data);
      });
   }.observes('model'),

   setSelected: function(selected) {
      var self = this;

      if (_.size(selected) != 1) {
         self.set('uri', null);
         return;
      }

      self.set('uri', _.first(_.values(selected)));
   },

   _updateFromSelection: function(roof_data) {
      var self = this;
      self.$('#dropWalls').prop('checked', roof_data.options.drop_walls ? true : false);

      self.$('#front').prop('checked', false);
      self.$('#back').prop('checked', false);
      self.$('#left').prop('checked', false);
      self.$('#right').prop('checked', false);

      _.forEach(roof_data.options.gradient, function(v, k) {
         if (v) {
            self.$('#' + k).prop('checked', true);
         }
      });
   },

   _applyDropWalls: function(checked) {
      var self = this;
      // Hacky.  Set the value to the old value, and just let the databinding
      // take care of any true updates.
      radiant.call_obj('stonehearth.building', 'set_roof_drop_walls', checked)
         .done(function() {
         })
         .fail(function(e) {
            console.assert(false, e);
         });
   },

   _toggleGradient: function(gradient, checked) {
      var self = this;

      radiant.call_obj('stonehearth.building', 'set_roof_gradients', gradient, checked)
         .done(function() {
         })
         .fail(function(e) {
            console.assert(false, e);
         });
   },

   actions: {
   }
});
