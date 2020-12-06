// used for functions that get used by multiple views
var stonehearth_ace = {
   _allTitles: {},
   _fence_mode: {},
   _storageFilterPresets: {},

   mergeInto: function(to_obj, from_obj) {
      radiant.each(from_obj, function(name, data) {
         if (Array.isArray(to_obj[name]) && Array.isArray(data)) {
            to_obj[name] = to_obj[name].concat(data);
         }
         else if (typeof to_obj[name] == 'object' && typeof data == 'object') {
            stonehearth_ace.mergeInto(to_obj[name], data);
         }
         else {
            to_obj[name] = data;
         }
      });
   },

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
         // first check if we have a special specification for this role
         if (stonehearth_ace._job_roles && stonehearth_ace._job_roles[thisRole]) {
            var roleData = stonehearth_ace._job_roles[thisRole];
            classArray.push({
               name: thisRole,
               readableName: roleData.display_name,
               description: roleData.description,
               icon: roleData.icon
            });
         }
         else {
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
            if (callbackFn) {
               callbackFn(data);
            }
         });
      }
   },

   getTitlesList: function(availableTitles, entityTitles, entityName, includeNextTitles) {
      var titlesArr = [];
      radiant.each(entityTitles, function(title, rank) {
         var lastRank = rank + (includeNextTitles ? 1 : 0);
         var lookups = availableTitles[title];
         if (lookups && lookups.ranks) {
            var ranksArr = [];
            radiant.each(lookups.ranks, function(_, rank_data) {
               if (rank_data.rank <= lastRank) {
                  ranksArr.push({
                     key: title + '|' + rank_data.rank,
                     title: title,
                     rank: rank_data.rank,
                     attained: rank_data.rank <= rank,
                     display_name: entityName + rank_data.display_name,
                     description: rank_data.description
                  });
               }
            });
            
            if (ranksArr.length > 0) {
               ranksArr.sort(function(a, b) {
                  return a.rank - b.rank;
               });

               titlesArr.push({
                  ordinal: lookups.ordinal || 999,
                  display_name: lookups.display_name,
                  description: lookups.description,
                  ranks: ranksArr
               });
            }
         }
      });
      titlesArr.sort(function(a, b) {
         return a.ordinal - b.ordinal;
      })

      return titlesArr;
   },

   createTitleSelectionList: function(availableTitles, entityTitles, entityUri, entityName) {
      if (stonehearth_ace._titleListContainer) {
         stonehearth_ace._titleListContainer.remove();
         delete stonehearth_ace._titleListContainer;
      }

      // first check if we actually have any titles for this entity
      if (entityTitles && availableTitles) {
         var titlesArr = stonehearth_ace.getTitlesList(availableTitles, entityTitles, entityName);

         if (titlesArr.length > 0) {
            var titleRanks = [];

            // insert the "none" option
            titleRanks.push({
               key: 'none',
               display_name: entityName,
               description: availableTitles.none && availableTitles.none.description || 'i18n(stonehearth_ace:data.population.ascendancy.titles.none.description)'
            });

            radiant.each(titlesArr, function(_, titleData) {
               titleRanks = titleRanks.concat(titleData.ranks);
            });

            var onChanged = function (key, value) {
               radiant.call('stonehearth_ace:select_title_command', entityUri, value.title, value.rank);
               // also dispose of the list
               result.container.remove();
            };
            var tooltipFn = function (div, value) {
               App.guiHelper.addTooltip(div, value.description, value.display_name);
            };

            var result = App.guiHelper.createCustomSelector('titleSelection', titleRanks, onChanged, {listOnly: true, tooltipFn: tooltipFn});
            // now we just need to properly position the list and display it
            stonehearth_ace._titleListContainer = result.container;
            result.titlesArr = titleRanks;
            return result;
         }
      }
   },

   getSeasonIcon: function(season) {
      var icon;
      if (stonehearth_ace._season_icons) {
         icon = stonehearth_ace._season_icons[season] || stonehearth_ace._season_icons['default'];
      }
      return icon;
   },

   getFenceModeData: function() {
      return stonehearth_ace._fence_mode;
   },

   updateFenceModeSettings: function(selected_segments, custom_presets) {
      stonehearth_ace._fence_mode.selected_segments = selected_segments || stonehearth_ace._fence_mode.selected_segments;
      stonehearth_ace._fence_mode.custom_presets = custom_presets || stonehearth_ace._fence_mode.custom_presets;
      return radiant.call('radiant:set_config', 'mods.stonehearth_ace.fence_mode', {
         selected_segments: stonehearth_ace._fence_mode.selected_segments,
         custom_presets: stonehearth_ace._fence_mode.custom_presets
      });
   },

   getStorageFilterPresets: function() {
      return stonehearth_ace._storageFilterPresets;
   },

   updateStorageFilterPresets: function(custom_presets) {
      stonehearth_ace._storageFilterPresets.custom_presets = custom_presets;
      return radiant.call('radiant:set_config', 'mods.stonehearth_ace.storage_filter_custom_presets', stonehearth_ace._storageFilterPresets.custom_presets);
   },

   getCommandGroup: function(name) {
      return stonehearth_ace._command_groups[name];
   },

   getModConfigSetting: function(mod, setting, callbackFn) {
      var configPath = `mods.${mod}.${setting}`;
      radiant.call('radiant:get_config', configPath)
      .done(function(o) {
         var value = o[configPath];
         if (value == null)
         {
            value = stonehearth_ace.getGameplaySettingDefaultValue(mod, setting);
         }
         
         callbackFn(value);
      });
   },

   getGameplaySettingDefaultValue: function(mod, setting) {
      var modSettings = stonehearth_ace._gameplay_settings[mod];
      var settingData = modSettings && modSettings[setting];
      return settingData && settingData.default;
   },
}

$.getJSON('/stonehearth_ace/ui/data/equipment_types.json', function(data) {
   radiant.each(data, function(type, type_data) {
      type_data.type = type;
   });
   stonehearth_ace._equipment_types = data;
});

$.getJSON('/stonehearth_ace/ui/data/season_icons.json', function(data) {
   stonehearth_ace._season_icons = data;
});

$.getJSON('/stonehearth_ace/ui/data/job_roles.json', function(data) {
   stonehearth_ace._job_roles = data;
});

$.getJSON('/stonehearth_ace/ui/data/fence_types.json', function(data) {
   stonehearth_ace._fence_mode.default_presets = data.default_presets;

   radiant.call('radiant:get_config', 'mods.stonehearth_ace.fence_mode')
      .done(function(response) {
         var settings = response['mods.stonehearth_ace.fence_mode'] || {};
         stonehearth_ace._fence_mode.selected_segments = settings.selected_segments;
         stonehearth_ace._fence_mode.custom_presets = settings.custom_presets || {};
      });
});

$.getJSON('/stonehearth_ace/ui/data/storage_filter_presets.json', function(data) {
   stonehearth_ace._storageFilterPresets = {
      'default_presets': data.presets,
      'default_preset_list': data.default_preset_list,
   };

   radiant.call('radiant:get_config', 'mods.stonehearth_ace.storage_filter_custom_presets')
      .done(function(response) {
         stonehearth_ace._storageFilterPresets.custom_presets = response['mods.stonehearth_ace.storage_filter_custom_presets'] || {};
      });
});

$.getJSON('/stonehearth_ace/ui/data/command_groups.json', function(data) {
   stonehearth_ace._command_groups = data.groups;
});

$.getJSON('/stonehearth_ace/data/gameplay_settings/gameplay_settings.json', function(data) {
   stonehearth_ace._gameplay_settings = data;
});

$(top).trigger('stonehearth_ace:initialized');
