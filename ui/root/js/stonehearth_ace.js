// used for functions that get used by multiple views
var stonehearth_ace = {
   _allTitles: {},

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
   },

   findRelevantClassesArray: function(roles) {
      var classes = {};
      var classArray = [];
      if ((typeof roles) === 'string') {
         roles = roles.split(" ");
      }
      var jobData = App.jobConstants;
      for( i=0; i<roles.length; i++ ) {
         var thisRole = roles[i];
         var roleInfo = App.roleConstants[thisRole];
         if (roleInfo) {
            radiant.each(roleInfo, function(targetClass, value) {
               var genericAlias = jobData[targetClass].description.generic_alias || targetClass;
               if (!classes[genericAlias]) {
                  classes[genericAlias] = true;
                  var classInfo = {
                     name : genericAlias,
                     readableName:  jobData[genericAlias].description.display_name, 
                     icon : jobData[genericAlias].description.icon
                  };
                  classArray.push(classInfo);
               }
            });
         }
      }
      return classArray;
   },

   loadAvailableTitles: function(json, callbackFn) {
      // when the selection changes, load up the appropriate titles json
      if (stonehearth_ace._allTitles[json])
      {
         if (callbackFn) {
            callbackFn(stonehearth_ace._allTitles[json]);
         }
      }
      else {
         $.getJSON(json, function(data) {
            stonehearth_ace._allTitles[json] = data;
            callbackFn(data);
         });
      }
   },

   createTitleSelectionList: function(availableTitles, entityTitles, entityUri, entityName) {
      if (stonehearth_ace._titleListContainer) {
         stonehearth_ace._titleListContainer.remove();
         delete stonehearth_ace._titleListContainer;
      }

      // first check if we actually have any titles for this entity
      if (entityTitles && availableTitles) {
         var titlesArr = [];
         radiant.each(entityTitles, function(title, rank) {
            var lookups = availableTitles[title];
            if (lookups && lookups.ranks) {
               radiant.each(lookups.ranks, function(_, rank_data) {
                  if (rank_data.rank <= rank) {
                     titlesArr.push({
                        key: title + '|' + rank_data.rank,
                        title: title,
                        rank: rank_data.rank,
                        display_name: entityName + rank_data.display_name,
                        description: rank_data.description
                     });
                  }
               });
            }
         });

         if (titlesArr.length > 0) {
            // insert the "none" option
            titlesArr.splice(0, 0, {
               key: 'none',
               display_name: entityName,
               description: availableTitles.none && availableTitles.none.description || 'i18n(stonehearth_ace:data.population.ascendancy.titles.none.description)'
            });

            var onChanged = function (key, value) {
               radiant.call('stonehearth_ace:select_title_command', entityUri, value.title, value.rank);
               // also dispose of the list
               result.container.remove();
            };
            var tooltipFn = function (div, value) {
               App.guiHelper.addTooltip(div, value.description, value.display_name);
            };

            var result = App.guiHelper.createCustomSelector('titleSelection', titlesArr, onChanged, {listOnly: true, tooltipFn: tooltipFn});
            // now we just need to properly position the list and display it
            stonehearth_ace._titleListContainer = result.container;
            result.titlesArr = titlesArr;
            return result;
         }
      }
   }
}

$.getJSON('/stonehearth_ace/ui/data/equipment_types.json', function(data) {
   radiant.each(data, function(type, type_data) {
      type_data.type = type;
   });
   stonehearth_ace._equipment_types = data;
});