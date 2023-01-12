$(document).ready(function(){
   var _peoplePicker = null;

   var _ownerAssignmentCallback = function(object, newOwner) {
      if (object && newOwner && newOwner.__self != object.get('stonehearth:pet.owner')) {
         radiant.call('stonehearth_ace:set_pet_owner', object.__self, newOwner.__self);
      }
   };

   var _ownerSortFunction = function(object, people) {
      var currentOwner = object.get('stonehearth:pet.owner');
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

   var _getOwnershipTooltip = function(object, person) {
      var currentOwner = object.get('stonehearth:pet.owner');
      var personUri = person.__self;
      if (currentOwner === personUri) {
         // this is the current owner of this object
         return "stonehearth:ui.game.people_picker.ownership_current_owner_tooltip";
      }

      return null;
   };

   var _hasCitizenOwner = function(object) {
      var currentOwner = object.get('stonehearth:pet.owner');
      return currentOwner != null;
   };

   var _noReservation = function(object) {
      var currentOwner = object.get('stonehearth:pet.owner');
      if (!currentOwner) {
         return "stonehearth_ace:ui.game.people_picker.already_no_owner";
      }

      return null;
   };

   $(top).on("radiant_assign_owner_to_pet", function (_, e) {
      var petUri = e.entity;

      if (!_peoplePicker || _peoplePicker.isDestroyed) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} )
         _peoplePicker = App.gameView.addView(App.StonehearthPeoplePickerView, {
            uri: petUri,
            onlyShowCitizens: true,
            showNoOwner: false,
            callback: _ownerAssignmentCallback,
            tooltipGenerator: _getOwnershipTooltip,
            sortFunction: _ownerSortFunction,
            hasCitizenOwner: _hasCitizenOwner,
            noOwnerCallback: _ownerAssignmentCallback,
            noOwnerTooltip: _noReservation,
         });
      } else {
         _peoplePicker.destroy();
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:jobs_close' });
         _peoplePicker = null;
      }
   });
});
