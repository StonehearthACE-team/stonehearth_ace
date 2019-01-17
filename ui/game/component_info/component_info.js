$(top).on('stonehearthReady', function (cc) {
   if (!App.gameView) {
      return;
   }
   var compInfo = App.gameView.getView(App.ComponentInfoView);
   if (!compInfo) {
      App.gameView.addView(App.ComponentInfoView, {});
   }
});

App.ComponentInfoView = App.View.extend({
   templateName: 'componentInfo',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,

   components: [],

   willDestroyElement: function() {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');

      self.$().off('click');

      self._super();
   },

   dismiss: function () {
      this.hide();
   },

   hide: function (animate) {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }

      this._super();
   },

   show: function (animate) {
      this._super();
      App.stonehearth.modalStack.push(this);
   },

   init: function() {
      var self = this;
      self._super();

      radiant.call_obj('stonehearth.selection', 'get_selected_command')
         .done(function(data) {
            self._onEntitySelected(data);
         });
   },

   didInsertElement: function () {
      var self = this;
      self._super();

      this.$().draggable({ handle: '.title' });

      // load up the default component data
      $.getJSON('/stonehearth_ace/data/component_info/component_info.json', function(data) {
         var sortedData = [];
         radiant.each(data, function(k, v) {
            v.name = k;
            sortedData.push(v);
         });
         sortedData.sort(function(a, b) {
            if (a.name < b.name) {
               return -1;
            }
            if (a.name > b.name) {
               return 1;
            }
            return 0;
         })
         
         self.set('generalDetails', sortedData);

         if (self.get('specificDetails')) {
            self._updateData();
         }
      });

      $(top).on("radiant_selection_changed.unit_frame", function (_, e) {
         self._onEntitySelected(e);
      });

      $(top).on("component_info_toggled", function (_, e) {
         if (self.visible()) {
            self.hide();
         }
         else {
            self.show();
            self._updateData();
         }
      });

      self.hide();
   },

   _onEntitySelected: function(e) {
      var self = this;
      var entity = e.selected_entity

      if (self.selectedEntityTrace) {
         self.selectedEntityTrace.destroy();
         self.selectedEntityTrace = null;
      }

      if (!entity) {
         self.hide();
         return;
      }

      self.selectedEntityTrace = new RadiantTrace();
      self.selectedEntityTrace.traceUri(entity, {'stonehearth_ace:component_info' : {}})
         .progress(function(result) {
            self.set('selectedDetails', result)
         })
         .fail(function(e) {
            console.log(e);
         });
   },

   _updateData: function() {
      var self = this;

      var general = self.get('generalDetails');

      if (general) {
         var selected = self.get('selectedDetails') || {};
         var specific = selected['stonehearth_ace:component_info'] || {};
         var data = [];

         radiant.each(general, function(_, component) {
            if (selected[component.name]) {
               // if the selected entity has this component, we're adding it to the list
               var entry = {
                  'icon': component.icon,
                  'displayName': component.display_name,
                  'generalDetails': component.description,
                  'specificDetails': []
               };

               var specificDetails = specific[component.name];
               if (specificDetails) {
                  radiant.each(specificDetails, function(_, detail) {
                     entry.specificDetails.push({
                        'details': detail.details,
                        'i18n_data': detail.i18n_data
                     });
                  });
               }

               data.push(entry);
            }
         });

         self.set('componentsInfo', data);

         var has_data = data.length > 0;
         if (!has_data && self.visible()) {
            self.hide();
         }

         $(top).trigger('selection_has_component_info_changed', {
            has_component_info: has_data
         });
      }
   }.observes('selectedDetails'),
});
