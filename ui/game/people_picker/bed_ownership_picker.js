$(document).ready(function(){
   var _peoplePicker = null;

   var ownerAssignmentCallback = function(object, newOwner) {
      if (object && newOwner) {
         radiant.call('stonehearth:set_owner_command', object.__self, newOwner.__self);
      }
   };

   var travelerAssignmentCallback = function(object) {
      if (object) {
         radiant.call('stonehearth:assign_exclusively_to_travelers', object.__self);
      }
   };

   var medicPatientAssignmentCallback = function(object) {
      if (object) {
         radiant.call('stonehearth_ace:assign_ownership_proxy', object.__self, 'medic_patient');
      }
   };

   var noOwnerAssignmentCallback = function(object) {
      if (object) {
         radiant.call('stonehearth_ace:remove_owner_command', object.__self);
      }
   };

   var canBeOwnerCallback = function(object, person) {
      if (!object) {
         return false;
      }

      if (object.get('player_id') != person.get('player_id')) {
         // Not in the same faction1
         return false;
      }

      var objectOwnableType = object.get('stonehearth:ownable_object.ownership_type');
      if (!objectOwnableType) {
         // Object cannot be owned
         return false;
      }

      var personAllowedToOwn = person.get('stonehearth:object_owner.allowed_ownerships.' + objectOwnableType);
      if (!personAllowedToOwn) {
         // Person cannot own this object's type
         return false;
      }

      return true;
   };

   var sortFunction = function(object, people) {
      var currentOwner = object.get('stonehearth:ownable_object.owner');
      if (currentOwner) {
         for (var i=0; i<people.length; ++i) {
            var person = people[i];
            if (person === currentOwner) {
               people[i] = people[0];
               people[0] = person;
               break;
            }
         }
      }

      return people;
   };

   var ownershipTooltip = function(object, person) {
      var currentOwner = object.get('stonehearth:ownable_object.owner');
      var personUri = person.__self;
      if (currentOwner === personUri) {
         // this is the current owner of this object
         return "stonehearth:ui.game.people_picker.ownership_current_owner_tooltip";
      }

      var objectOwnableType = object.get('stonehearth:ownable_object.ownership_type');
      var ownedObject = person.get('stonehearth:object_owner.owned_objects.' + objectOwnableType);
      if (ownedObject) {
         return "stonehearth:ui.game.people_picker.ownership_owns_another_tooltip";
      }

      return null;
   };

   var travelerReserved = function(object) {
      var ownerType = object.get('stonehearth:ownable_object.reservation_type');
      if (ownerType === 'traveler') {
         return "stonehearth:ui.game.people_picker.already_reserved_for_travelers";
      }

      return null;
   };

   var medicPatientReserved = function(object) {
      var ownerType = object.get('stonehearth:ownable_object.reservation_type');
      if (ownerType === App.constants.healing.PRIORITY_CARE_OWNERSHIP_TYPE) {
         return "stonehearth_ace:ui.game.people_picker.already_reserved_for_medic_patients";
      }

      return null;
   };

   var noReservation = function(object) {
      var owner = object.get('stonehearth:ownable_object.owner');
      if (!owner) {
         return "stonehearth_ace:ui.game.people_picker.already_no_owner";
      }

      return null;
   };

   var bedHasCitizenOwner = function(object) {
      var currentOwner = object.get('stonehearth:ownable_object.owner');
      var ownerType = object.get('stonehearth:ownable_object.reservation_type');
      return currentOwner && ownerType === 'citizen';
   };

   var bedHasTravelerOwner = function(object) {
      var currentOwner = object.get('stonehearth:ownable_object.owner');
      var ownerType = object.get('stonehearth:ownable_object.reservation_type');
      return currentOwner && ownerType === 'traveler';
   };

   var bedHasMedicPatientOwner = function(object) {
      var currentOwner = object.get('stonehearth:ownable_object.owner');
      var ownerType = object.get('stonehearth:ownable_object.reservation_type');
      return currentOwner && ownerType === App.constants.healing.PRIORITY_CARE_OWNERSHIP_TYPE;
   };

   $(top).on("radiant_assign_owner_to_entity", function (_, e) {
      var itemUri = e.entity;

      if (!_peoplePicker || _peoplePicker.isDestroyed) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} )
         _peoplePicker = App.gameView.addView(App.StonehearthPeoplePickerView,
                                                { uri: itemUri,
                                                  callback: ownerAssignmentCallback,
                                                  personFilter: canBeOwnerCallback,
                                                  tooltipGenerator: ownershipTooltip,
                                                  sortFunction: sortFunction,
                                                  travelerCallback: travelerAssignmentCallback,
                                                  travelerTooltip: travelerReserved,
                                                  medicPatientCallback: medicPatientAssignmentCallback,
                                                  medicPatientTooltip: medicPatientReserved,
                                                  noOwnerCallback: noOwnerAssignmentCallback,
                                                  noOwnerTooltip: noReservation,
                                                  hasCitizenOwner: bedHasCitizenOwner,
                                                  hasTravelerOwner: bedHasTravelerOwner,
                                                  hasMedicPatientOwner: bedHasMedicPatientOwner });
      } else {
         _peoplePicker.destroy();
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:jobs_close' });
         _peoplePicker = null;
      }
   });
});
