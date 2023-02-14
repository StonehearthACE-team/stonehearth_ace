App.StonehearthBuildingCostListView = App.View.extend({
   templateName: 'costList',
   i18nNamespace: 'stonehearth',
   uriProperty: 'model',

   components: {
      'stonehearth:build2:building' : '*'
   },

   init: function() {
      var self = this;
      self._super();

      //init usable object tracker
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:usable_item_tracker')
         .done(function(response) {
            self.tracker = response.tracker;
            self._installTrace();
         });

      radiant.call('stonehearth:get_client_service', 'building')
         .done(function(e) {
            self._onServiceReady(e.result);
         });
   },

   _onServiceReady: function(service) {
      var self = this;

      self._building_service = service;
      self._building_service_trace = radiant.trace(self._building_service).progress(function(change) {
         if (change.current_building != self._current_building) {
            self._current_building = change.current_building;
            self.set('uri', change.current_building);
         } else {
            self._onBuildingChanged();
         }
      });
   },

   _onBuildingChanged: function() {
      var self = this;

      var building = self.get('model');
      if (!building) {
         return;
      }
      var building_c = building['stonehearth:build2:building'];

      if (!building_c) {
         return;
      }

      self._resource_cost = building_c.resource_cost;
      self._item_cost = building_c.item_cost;

      self._updateAvailable();

   }.observes('model'),

   _onResourcesChanged: function() {
      var self = this;

      var building = self.get('model');
      if (!building) {
         return;
      }
      var building_c = building['stonehearth:build2:building'];
      if (!building_c) {
         return;
      }

      self._resource_cost = building_c.resource_cost;
      self._item_cost = building_c.item_cost;
      self._updateAvailable();
   }.observes('model.stonehearth:build2:building.resource_cost'),

   _onItemsChanged: function() {
      var self = this;

      var building = self.get('model');
      if (!building) {
         return;
      }
      var building_c = building['stonehearth:build2:building'];
      if (!building_c) {
         return;
      }

      self._resource_cost = building_c.resource_cost;
      self._item_cost = building_c.item_cost;
      self._updateAvailable();
   }.observes('model.stonehearth:build2:building.item_cost'),

   didInsertElement: function() {
      var self = this;
      this._super();
   },

   becameVisible: function() {
      this._installTrace();
   },

   becameHidden: function() {
      this._destroyTrace();
   },

   _installTrace: function() {
      var self = this;
      if (self._playerUsableInventoryTrace) {
         return;
      }
      var itemTraces = {
         "tracking_data" : {}
      };
      self._playerUsableInventoryTrace = new StonehearthDataTrace(self.tracker, itemTraces)
         .progress(function(response) {
            self.usableInventoryTracker = response.tracking_data;
            self._updateAvailable();
         });
      
      // ACE: consider who can craft fixtures to inform the player when costs aren't fully satisfied
      App.jobController.addChangeCallback('stonehearth_ace:building3:cost_list', function() {
         self._updateCraftableItems();
         self._updateAvailable();
      }, true);
   },

   _destroyTrace: function() {
      if (this._playerUsableInventoryTrace) {
         this._playerUsableInventoryTrace.destroy();
         this._playerUsableInventoryTrace = null;
      }
      App.jobController.removeChangeCallback('stonehearth_ace:building3:cost_list');
   },

   //Right now this is never called, b/c the building editor is created and never destroyed.
   //If this ever changes, double make sure this works right!
   destroy: function() {
      this._destroyTrace();
      this._super();
   },

   _materialToViewData: function(material, count) {
      var self = this;
      var formatting = App.resourceConstants.resources[material];
      if (formatting) {
         // Convert from raw count to stacks.
         count = Math.ceil(count / formatting.stacks);
      }
      var ingredientData = {
         kind : 'material',
         identifier : material
      };
      var numHave = radiant.findUsableCount(ingredientData, self.usableInventoryTracker);

      var entry = {
         name: formatting.name,
         icon: formatting.icon,
         count: count,
         available: numHave,
         material : material,
         avaiable : numHave,
         requirementsMet : numHave >= count
      };

      return entry;
   },

   _itemToViewData: function(uri, count) {
      var self = this;

      var quality;
      if (uri.indexOf(App.constants.item_quality.KEY_SEPARATOR) == -1) {
         quality = 1;
      } else {
         var parts = uri.split(App.constants.item_quality.KEY_SEPARATOR);
         uri = parts[0];
         quality = parts[1];
      }

      var catalogData = App.catalog.getCatalogData(uri);
      if (!catalogData || !catalogData.iconic_uri) {
         return null;
      }

      var emberIconicKey = catalogData.iconic_uri.replace(/\./g, "&#46;");

      var ingredientData = {};
      ingredientData.kind = 'uri';
      ingredientData.identifier = emberIconicKey;
      if (quality && quality > 0) {
         ingredientData.quality = quality;
      }
      var availableCount = radiant.findUsableCount(ingredientData, self.usableInventoryTracker);
      var craftable = self._getItemCraftable(uri);

      var entry = {
         name: catalogData.display_name,
         icon: catalogData.icon,
         count: count,
         uri: uri,
         quality: quality,
         iconic_uri: emberIconicKey,
         available: availableCount,
         requirementsMet: (availableCount >= count),
         recipeUnlocked: craftable != null,
         recipeCraftable: craftable && craftable.craftable || false
      };

      return entry;
   },

   _getItemCraftable: function(uri) {
      var self = this;
      return self._craftableItems && self._craftableItems[uri];
   },

   _updateCraftableItems: function() {
      var self = this;

      var craftableProducts = {};
      var jobData = App.jobController.getJobControllerData();
      if (!jobData || !jobData.jobs) {
         return;
      }

      _.forEach(jobData.jobs, function(jobControllerInfo, jobUri) {
         if (!jobControllerInfo.recipe_list) {
            return;
         }

         var highestLevel = jobControllerInfo.highest_level;

         _.forEach(jobControllerInfo.recipe_list, function(category) {
            _.forEach(category.recipes, function(recipe_info, recipe_key) {
               var recipe = recipe_info.recipe;

               if (recipe.manual_unlock && !jobControllerInfo.manually_unlocked[recipe.recipe_key]) {
                  // do not show if no one can craft it
                  return;
               }

               var product_uri = recipe.product_uri;
               var craftable = craftableProducts[product_uri];
               if (!craftable) {
                  craftable = { crafters: [] };
                  craftableProducts[product_uri] = craftable;
               }

               var jobCraftable;
               for (var i = 0; i < craftable.crafters.count; i++) {
                  if (craftable.crafters[i].jobUri == jobUri) {
                     jobCraftable = craftable.crafters[i];
                     break;
                  }
               }

               if (!jobCraftable) {
                  jobCraftable = { jobUri: jobUri};
                  craftable.crafters.push(jobCraftable);
               }

               if (!jobCraftable.level || jobCraftable.level > recipe.level_requirement) {
                  jobCraftable.level = recipe.level_requirement || 1;
                  jobCraftable.craftable = jobControllerInfo.num_members > 0 && jobCraftable.level <= highestLevel;
               }
            });
         });
      });

      radiant.each(craftableProducts, function(uri, craftable) {
         var isCraftable = false;
         _.forEach(craftable.crafters, function(jobCraftable) {
            isCraftable |= jobCraftable.craftable;
         });
         craftable.craftable = isCraftable;
      });

      self._craftableItems = craftableProducts;
   },

   _updateAvailable: function() {
      var self = this;

      if (!self._resource_cost || !self._item_cost || !self.usableInventoryTracker) {
         return;
      }

      var arr = [];
      _.forEach(self._resource_cost, function(count, material) {
         var entry = self._materialToViewData(material, count);
         if (entry && entry.count > 0) {
            arr.push(entry);
         }
      });

      _.forEach(self._item_cost, function(count, uri) {
         var entry = self._itemToViewData(uri, count);
         if (entry && entry.count > 0) {
            arr.push(entry);
         }
      });

      self.set('building_cost', arr);
   },

   // ACE: show additional informational tooltips on missing fixtures
   _availableUpdated: function() {
      var self = this;
      Ember.run.scheduleOnce('afterRender', this, function() {
         self.$('tr.costMissing').each(function() {
            var $elem = $(this);
            App.tooltipHelper.createDynamicTooltip($elem, function () {
               var uri = $elem.attr('data-uri');

               if (uri) {
                  // we don't have enough of it, and there's a uri, so it's not a material
                  // either we can craft it, we can't craft due to missing crafter, or we can't craft due to missing recipe

                  var craftable = self._getItemCraftable(uri);

                  if (craftable) {
                     // we can craft it, or are missing a crafter
                     var isCraftable = craftable.craftable;
                     var uriCrafters = craftable.crafters;

                     if (isCraftable) {
                        // we can craft it, no need for a warning message
                        return null;
                     }
                     else {
                        // missing a crafter; list all the crafters and required levels that could craft it
                        var tooltipString = i18n.t('stonehearth_ace:ui.game.build_mode2.cost_list.missing_crafter_description');
                        uriCrafters.forEach(function(crafter) {
                           var jobInfo = App.jobConstants[crafter.jobUri];
                           if (jobInfo) {
                              var text = i18n.t('stonehearth:ui.game.citizen_character_sheet.level_abbreviation') +
                                    ` <span class="required-level">${crafter.level}</span> ${i18n.t(jobInfo.description.display_name)}`
                              var iconDiv = `<img src="${jobInfo.description.icon}"/>`;
                              var div = `<div class="tooltip-missing-crafter">${text}${iconDiv}</div>`;
                              tooltipString += div;
                           }
                        });

                        return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.build_mode2.cost_list.missing_crafter_title'), tooltipString));
                     }
                  }
                  else {
                     // no recipe!
                     var tooltipString = i18n.t('stonehearth_ace:ui.game.build_mode2.cost_list.missing_recipe_description');
                     return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.build_mode2.cost_list.missing_recipe_title'), tooltipString));
                  }
               }
               else {
                  return null;
               }
            });
         });
      });
   }.observes('building_cost'),
});
