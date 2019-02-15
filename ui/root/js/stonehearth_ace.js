// used for functions that get used by multiple views
var stonehearth_ace = {
   getEquipmentTypesArray: function(equipment_types) {
      if (!equipment_types) {
         return stonehearth_ace._equipment_types;
      }
      if (stonehearth_ace._equipment_types) {
         var result = {};
         var overridden = {};
         radiant.each(equipment_types, function(type, _) {
            // only check for this type if it's not already being overridden
            if (!overridden[type]) {
               var this_type = stonehearth_ace._getEquipmentType(overridden, type);
               if (this_type) {
                  // check if this type overrides any existing types
                  if (this_type.overrides) {
                     radiant.each(this_type.overrides, function(_, override) {
                        if (!overridden[override]) {
                           overridden[override] = true;
                           delete result[override];
                        }
                     });
                  }

                  result[this_type.type] = {
                     "name": this_type.name,
                     "icon": this_type.icon
                  }
               }
            }
         });

         return radiant.map_to_array(result);
      }
   },

   _getEquipmentType: function(overridden, equipment_type) {
      var this_type = stonehearth_ace._equipment_types[equipment_type];
      if (this_type) {
         if (this_type.redirect) {
            overridden[equipment_type] = true;
            return stonehearth_ace._getEquipmentType(overridden, this_type.redirect);
         }

         return this_type;
      }
   },

   getEquipmentTypesString: function(typeArray) {
      var typeString = '';
      for (i=0; i<typeArray.length; i++) {
         if (i==0) {
            typeString += typeArray[i].name;
         } else {
            typeString += ', ' + typeArray[i].name;
         }
      }
      return typeString;
   }
}

$.getJSON('/stonehearth_ace/ui/data/equipment_types.json', function(data) {
   radiant.each(data, function(type, type_data) {
      type_data.type = type;
   });
   stonehearth_ace._equipment_types = data;
});