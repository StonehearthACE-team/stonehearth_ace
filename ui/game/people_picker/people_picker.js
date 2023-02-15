App.StonehearthPeoplePickerView = App.View.extend({
   templateName: 'stonehearthPeoplePicker',
   closeOnEsc: true,
   uriProperty: 'model',
   components: {
      'stonehearth:unit_info': {},
      'stonehearth:ownable_object': {},
      // ACE: extra components for non-bed-owner people picking
      'stonehearth:pet': {},
      'stonehearth_ace:periodic_interaction': {},
   },

   callback: null,
   personFilter: null,
   tooltipGenerator: null,
   sortFunction: null,
   travelerCallback: null,
   travelerTooltip: null,
   hasCitizenOwner: null,
   medicPatientCallback: null,
   medicPatientTooltip: null,
   noOwnerCallback: null,
   noOwnerTooltip: null,

   init: function() {
      this._super();
      var self = this;
      self._popTrace = App.population.getTrace();
      self._popTrace.progress(function(pop) {
            var citizensArray = radiant.map_to_array(pop.citizens, self._citizensMapFilter);
            self.set('citizensArrayData', citizensArray);
            var cityTier = pop.city_tier;
            self.set('cityTier', cityTier);
         });
   },

   destroy: function() {
      $(top).off('radiant_selection_changed.people_picker');

      if (this.selectedEntityTrace) {
         this.selectedEntityTrace.destroy();
         this.selectedEntityTrace = null;
      }

      if (this._popTrace) {
         this._popTrace.destroy();
         this._popTrace = null;
      }
      this._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      // update UI when object selected has changed
      $(top).on("radiant_selection_changed.people_picker", function (_, data) {
         self._onEntitySelected(data);
      });
   },

   _onObjectTraced: function() {
      var self = this;
      var object = self.get('model');
      var citizensArray = self.get('citizensArrayData');
      if (object && citizensArray) {
         var newArray = citizensArray;
         if (self.sortFunction) {
            newArray = self.sortFunction(object, citizensArray);
         }
         self.set('citizensArray', newArray);
         self.notifyPropertyChange('citizensArray');
      }
   }.observes('model', 'citizensArrayData'),

   // the citizens map from the population trace returns different values
   // than the population data's citizen map, so make sure they both
   // return only the game object urls for each citizen
   _citizensMapFilter: function(k, v) {
      if (k === 'size') {
         return false; // ignore size field from population data
      }
      if (v.__self) {
         return v.__self; // get game object id
      }
   },

   selectPerson: function(person) {
      if (this.callback) {
         this.callback(this.get('model'), person);
         this.callback = null;
      }
      this.destroy();
   },

   shouldShowPerson: function(person) {
      if (this.personFilter) {
         return this.personFilter(this.get('model'), person);
      }
      return true;
   },

   getTooltip: function(person) {
      if (this.tooltipGenerator) {
         return this.tooltipGenerator(this.get('model'), person);
      }
      return null;
   },

   _onEntitySelected: function(e) {
      var self = this;
      var entity = e.selected_entity

      if (self.isDestroying || self.isDestroyed) {
         return;
      }

      if (!entity) {
         self.destroy();
      }

      if (self.selectedEntityTrace) {
         self.selectedEntityTrace.destroy();
      }

      self.selectedEntityTrace = new StonehearthDataTrace(entity, self.components)
         .progress(function(result) {
            if (result.get('stonehearth:ownable_object')) {
               self.set('uri', result.__self); // set uri for newly selected entity

               var pop = App.population.getPopulationData();
               if (pop) {
                  if (pop.citizens && pop.citizens.size != null) {
                     var citizens = radiant.map_to_array(pop.citizens, self._citizensMapFilter);
                     self.set('citizensArrayData', citizens);
                  }
               }
            } else {
               self.destroy();
            }
         })
         .fail(function(e) {
            console.log(e);
         });
   },

   actions: {
      selectTraveler: function() {
         if (this.travelerCallback) {
            this.travelerCallback(this.get('model'));
            this.travelerCallback = null;
            this.set('travelerChanged', true); // used to ensure property is recalculated
         }
         this.destroy();
      },

      selectMedicPatient: function() {
         if (this.medicPatientCallback) {
            this.medicPatientCallback(this.get('model'));
            this.medicPatientCallback = null;
            this.set('medicPatientChanged', true); // used to ensure property is recalculated
         }
         this.destroy();
      },

      selectNone: function() {
         if (this.noOwnerCallback) {
            this.noOwnerCallback(this.get('model'));
            this.noOwnerCallback = null;
            this.set('noOwnerChanged', true); // used to ensure property is recalculated
         }
         this.destroy();
      }
   },

   shouldShowTravelerReserve: function() {
      return this.get('cityTier') >= App.constants.traveler.MIN_CITY_TIER;
   }.property('cityTier'),

   travelerReservedText: function() {
      if (this.travelerTooltip && this.get('model')) {
         return this.travelerTooltip(this.get('model'));
      }
      return null;
   }.property('model.stonehearth:ownable_object'),

   _putTravelerReservationAtTop: function() {
      if (this.hasCitizenOwner && this.get('model')) {
         return !this.hasCitizenOwner(this.get('model'));
      }
      return true;
   },

   // ACE: extra options
   noOwnerText: function() {
      if (this.noOwnerTooltip && this.get('model')) {
         return this.noOwnerTooltip(this.get('model'));
      }
      return null;
   }.property('model.stonehearth:ownable_object'),

   medicPatientReservedText: function() {
      if (this.medicPatientTooltip && this.get('model')) {
         return this.medicPatientTooltip(this.get('model'));
      }
      return null;
   }.property('model.stonehearth:ownable_object'),

   _hasCitizenOwner: function() {
      if (this.hasCitizenOwner && this.get('model')) {
         return this.hasCitizenOwner(this.get('model'));
      }
      return true;
   },

   _hasTravelerOwner: function() {
      if (this.hasTravelerOwner && this.get('model')) {
         return this.hasTravelerOwner(this.get('model'));
      }
      return false
   },

   _hasMedicPatientOwner: function() {
      if (this.hasMedicPatientOwner && this.get('model')) {
         return this.hasMedicPatientOwner(this.get('model'));
      }
      return false
   },

   // Returns an array of all rows for the people picker.
   // Citizens will have a string, such as "object://game/6017",
   // while the row for traveler reservation has an object
   // containing the field isTraveler.
   // ACE: handle medic patient and no owner options
   pickerRows: function() {
      var citizens = this.get('citizensArray');
      if (citizens) {
         var rows = radiant.map_to_array(radiant.shallow_copy(citizens));
         var noOwner = { noOwner: true };
         if (!this.onlyShowCitizens) {
            // put a "none" ownership option right at the top (under any ownership)
            var nonCitizenRows = [noOwner];
            if (this._hasTravelerOwner()) {
               nonCitizenRows.unshift({ isTraveler: true });
            }
            else {
               nonCitizenRows.push({ isTraveler: true });
            }
            if (this._hasMedicPatientOwner()) {
               nonCitizenRows.unshift({ isMedicPatient: true });
            }
            else {
               nonCitizenRows.push({ isMedicPatient: true });
            }
            
            if (this._hasCitizenOwner()) {
               rows.splice(1, 0, ...nonCitizenRows);
            }
            else {
               rows.unshift(...nonCitizenRows);
            }

            this.set('travelerChanged', false);
            this.set('medicPatientChanged', false);
         }
         else if (this.showNoOwner != false) {
            if (this._hasCitizenOwner()) {
               rows.splice(1, 0, noOwner);
            }
            else {
               rows.unshift(noOwner);
            }
         }
         this.set('noOwnerChanged', false);
         return rows;
      }
   }.property('model', 'citizensArray', 'travelerChanged', 'medicPatientChanged', 'noOwnerChanged')
});

App.StonehearthPeoplePickerRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'stonehearthPeoplePickerRow',
   uriProperty: 'model',

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:job" : {
      },
      'stonehearth:object_owner': {}
   },

   didInsertElement: function() {
      var self = this;
      self.$().on( 'click', '.selectable_citizen_row', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         radiant.call('stonehearth:camera_look_at_entity', self.uri)
         radiant.call('stonehearth:select_entity', self.uri);
      });
   },

   actions: {
      selectPerson: function(citizen) {
         if (this.pickerView) {
            this.pickerView.selectPerson(citizen)
         }
      }
   },

   //Only add people to the list if they pass the people filter
   shouldShow: function() {
      if (this.pickerView && this.get('model')) {
         return this.pickerView.shouldShowPerson(this.get('model'));
      }

      return true;
   }.property('model.stonehearth:object_owner'),

   //Only add pple to the list if they are not already in the party, and if they are a combat class
   additionalText: function() {
      if (this.pickerView && this.get('model')) {
         return this.pickerView.getTooltip(this.get('model'));
      }

      return null;
   }.property('model'),
});
