App.StonehearthPeoplePickerView.reopen({
   medicPatientCallback: null,
   medicPatientTooltip: null,

   actions: {
      selectMedicPatient: function() {
         if (this.medicPatientCallback) {
            this.medicPatientCallback(this.get('model'));
            this.medicPatientCallback = null;
            this.set('medicPatientChanged', true); // used to ensure property is recalculated
         }
         this.destroy();
      }
   },

   medicPatientReservedText: function() {
      if (this.medicPatientTooltip && this.get('model')) {
         return this.medicPatientTooltip(this.get('model'));
      }
      return null;
   }.property('model.stonehearth:ownable_object'),

   _reallyPutTravelerReservationAtTop: function() {
      if (this.hasTravelerOwner && this.get('model')) {
         return this.hasTravelerOwner(this.get('model'));
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
         if (this._putTravelerReservationAtTop()) {
            // additional check for whether it should be traveler first and then medic
            if (this._reallyPutTravelerReservationAtTop()) {
               rows.unshift({ isTraveler: true }, { isMedicPatient: true });
            }
            else {
               rows.unshift({ isMedicPatient: true }, { isTraveler: true });
            }
         } else {
            rows.splice(1, 0, { isMedicPatient: true }, { isTraveler: true });
         }
         this.set('travelerChanged', false);
         return rows;
      }
   }.property('model', 'citizensArray', 'travelerChanged', 'medicPatientChanged')
});
