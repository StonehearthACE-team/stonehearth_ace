App.StonehearthPeoplePickerView.reopen({
   components: {
      'stonehearth:unit_info': {},
      'stonehearth:ownable_object': {},
      'stonehearth:pet': {},
      'stonehearth_ace:periodic_interaction': {},
   },

   medicPatientCallback: null,
   medicPatientTooltip: null,
   noOwnerCallback: null,
   noOwnerTooltip: null,

   actions: {
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
