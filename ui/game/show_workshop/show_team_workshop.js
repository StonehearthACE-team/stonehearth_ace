var _showSelectedWorkshopCrafting = false;
var _craftSearchChecks = null;

$(top).on('stonehearthReady', function() {
   // need to apply the settings on load as well
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_selected_workshop_crafting', function(value) {
      $(top).trigger('show_selected_workshop_crafting_changed', { value: value });
   });
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'default_craft_search_checks', function(value) {
      $(top).trigger('default_craft_search_checks_changed', { value: value });
   });

   $(top).on("radiant_selection_changed.show_team_workshop", function (_, e) {
      App.workshopManager._selectedEntityTraceDone = false;
      if (e && e.selected_entity) {
         App.workshopManager.selectedEntityTrace = new RadiantTrace(e.selected_entity)
            .progress(function(result) {
               if (App.workshopManager._selectedEntityTraceDone) {
                  return;
               }
               App.workshopManager._selectedEntityTraceDone = true;

               var data = {};
               if (result && result['stonehearth:workshop']) {
                  data.uri = result.uri;
                  data.entity = result;
               }

               if (!App.workshopManager.selectedWorkshopEntity || App.workshopManager.selectedWorkshopEntity.uri != data.uri) {
                  App.workshopManager.selectedWorkshopEntity = data;
                  $(top).trigger('selected_workshop_entity_changed', data);
               }
            });
      }
      else {
         var data = {};
         App.workshopManager.selectedWorkshopEntity = data;
         $(top).trigger('selected_workshop_entity_changed', data);
      }
   });

   $(top).on("show_selected_workshop_crafting_changed", function (_, e) {
      _showSelectedWorkshopCrafting = e.value;
   });

   $(top).on("default_craft_search_checks_changed", function (_, e) {
      _craftSearchChecks = e.value;
   });
   
   App.workshopManager.pauseOrResumeTrackingItems = $.debounce(1, function () {
      var self = this;
      if (!self.usableItemTracker) return;  // We'll be called later.
      var anyWorkshopVisible = _.any(self.workshops, function (w) { return w.isVisible; });
      if (anyWorkshopVisible && !self.usableItemTrackerTrace) {
         var itemTraces = {
            "tracking_data" : {
               "stonehearth:loot:gold" : {
                  "items" : {
                     "*" : {
                        "stonehearth:stacks": {}
                     }
                  }
               }
            }
         };
         self.usableItemTrackerTrace = new StonehearthDataTrace(self.usableItemTracker, itemTraces)
            .progress(function (response) {
               self.usableItemTrackerData = response.tracking_data;
               self.notifyItemsChanged();
            });
      } else if (!anyWorkshopVisible && self.usableItemTrackerTrace) {
         self.usableItemTrackerTrace.destroy();
         self.usableItemTrackerTrace = null;
      }
   });

   if (App.workshopManager.usableItemTrackerTrace) {
      App.workshopManager.usableItemTrackerTrace.destroy();
      App.workshopManager.usableItemTrackerTrace = null;
   }

   App.StonehearthTeamCrafterView.reopen({
      SHIFT_KEY_ACTIVE: false,
      ace_components: {
         "members": {
            "*": {
               "stonehearth:job": {
                  "curr_job_controller": {}
               },
               "stonehearth:unit_info": {}
            }
         }
      },

      init: function() {
         var self = this;
         stonehearth_ace.mergeInto(self.components, self.ace_components);
   
         self._super();
      },

      didInsertElement: function() {
         this._super();
         var self = this;

         // Craft or maintain on click/ctrl+click of right mouse button.
         // Replaces the original in super to incorporate the ability to specify the position of the order.
         this.$('#recipeItems').off('mousedown.craftOrMaintain', '.item');
         this.$('#recipeItems').on('mousedown.craftOrMaintain', '.item', function (e) {
            var orderArgs;
            if (e.button == 2) {
               if (e.ctrlKey) {
                  orderArgs = { type: "maintain", at_least: 1 };
               } else {
                  orderArgs = { type: "make", amount: 1 };
               }
               if (e.shiftKey) {
                  orderArgs.order_index = 1;
               }
            }
            if (orderArgs) {
               var recipe = self._getOrCalculateRecipeData($(this).attr('recipe_key'));
               radiant.call_obj(self.getOrderList(), 'add_order_command', recipe, orderArgs)
                  .done(function(return_data){
                     if (self.isDestroyed || self.isDestroying) {
                        return;
                     }
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:confirm'} );
                  });
            }
         });

         //Cancel order from the order list menu with click of right mouse button.
         // Replaces the original in super to incorporate the ability to also remove associated orders.
         self.$('#orders').off('mousedown.existingOrderClick', '.orderListItem');
         self.$('#orders').on('mousedown.existingOrderClick', '.orderListItem', function (e) {
            if (e.button == 2) {
               var orderList = self.getOrderList();
               var item = $(this);
               var orderId = parseInt(item.attr("data-orderid"));
               var deleteAssociatedOrders = self.SHIFT_KEY_ACTIVE;
               radiant.call_obj(orderList, 'delete_order_command', orderId, deleteAssociatedOrders)
                  .done(function(return_data){
                     item.remove();
                     if (return_data && return_data.associated_orders) {
                        radiant.each(return_data.associated_orders, function(_, order_id) {
                           $('#orders').find("[data-orderid='"+order_id+"']").remove();
                        })
                     }
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash'} );
                  });
            }
         });

         self._updateCraftOrderPreference();

         $(top).on("selected_workshop_entity_changed", function (_, e) {
            if (_showSelectedWorkshopCrafting) {
               self._updateSelectedWorkshopEntity(e, true);
            }
         });

         $(top).on("show_selected_workshop_crafting_changed", function (_, e) {
            // in case _showSelectedWorkshopCrafting hasn't been updated yet, use e.value
            self._updateSelectedWorkshopEntity(null, e.value);
         });

         $(top).on("default_craft_search_checks_changed", function (_, e) {
            self._updateCraftSearchChecks(e.value);
         });

         self._updateCraftSearchChecks(_craftSearchChecks);

         self.$('#craftingWindow').on('click', '.categoryCrafter', function() {
            var $elem = $(this);
            var id = $elem.attr('crafterId');
            var category = $elem.attr('category');
            var disable = $elem.hasClass('enabledCrafting');

            var member = self._memberLookup[id];
            if (member) {
               radiant.call('stonehearth_ace:set_crafting_category_disabled', member.objectRef, category, disable);

               // also update the status so it toggles the class on the element
               var categoryMember = member.categoryMembers[category];
               if (categoryMember) {
                  Ember.set(categoryMember, 'disabled', disable);
               }
            }
         });
      },

      willDestroyElement: function () {
         var self = this;
         self._super();

         self.$('#craftButton').off('hover');
         self.$(".category").off('mouseenter mouseleave', '.item');
         self.$('#orders').off('scroll');
         self.$('#searchSettingContainer').off('change.refocusInput', '.searchSettingCheckbox');
         self.$('#searchContainer').off('focusin');
         self.$('#searchContainer').off('focusout');
         if (self._timeoutID != null) {
            clearTimeout(self._timeoutID);
            self._timeoutID = null;
         }
      },

      _updateCategoryCraftersTooltips: function() {
         // when the recipes get updated, wait for Ember.run.scheduleOnce('afterRender',) and then do dynamic tooltips
         var self = this;
         Ember.run.scheduleOnce('afterRender', function() {
            self.$('.categoryCrafter').each(function() {
               var $elem = $(this);
               App.tooltipHelper.createDynamicTooltip($elem, function () {
                  var id = $elem.attr('crafterId');
                  var category = $elem.attr('category');
                  var disable = $elem.hasClass('enabledCrafting');

                  var member = self._memberLookup[id];
                  if (member) {
                     var data = {
                        name: member.name,
                        level: member.level,
                     };

                     var tooltipString = disable && i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.disable_description', data) ||
                           i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.enable_description', data);

                     return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.title'), tooltipString));
                  }
               });
            });
         });
      }.observes('recipes'),

      // ACE: overriding just to also put the i18n.t-ed description in
      _buildRecipeArray: function () {
         var self = this;
         if (self.isDestroying || self.isDestroyed) {
            return;
         }

         var members = this.get('model.members');
         var memberLookup = {};
         var memberArray = [];
         radiant.each(members, function(id, member) {
            var job = member['stonehearth:job'];
            var jobController = job && job.curr_job_controller;
            if (jobController) {
               var name = member['stonehearth:unit_info'].custom_name;
               var level = jobController.last_gained_lv;
               var disabledCategories = jobController.disabled_crafting_categories;

               var memberStruct = {
                  objectRef: member.__self,
                  id: id,
                  name: name,
                  level: level,
                  disabledCategories: disabledCategories,
                  categoryMembers: {},
               };
               memberArray.push(memberStruct);
               memberLookup[id] = memberStruct;
            }
         });

         self._memberLookup = memberLookup;
         // sort first by level, then by entity id
         // they're both numeric, and 0 equates to false, so we can do it with one expression
         memberArray.sort((a, b) => (a.level - b.level) || (a.id - b.id));
   
         var recipes = this.get('model.recipe_list');
         var recipe_categories = [];
         self.allRecipes = {};
   
         var manuallyUnlockedRecipes = self.get('model.manually_unlocked');
         var highestLevel = self.get('model.highest_level');
   
         radiant.each(recipes, function(category_id, category) {
            var recipe_array = [];
            var category_has_visible_recipes = false;
            radiant.each(category.recipes, function(recipe_key, recipe_info) {
               var recipe = recipe_info.recipe
               var formatted_recipe = radiant.shallow_copy(recipe);
               formatted_recipe.needs_ingredient_formatting = true;
   
               formatted_recipe.display_name = i18n.t(formatted_recipe.recipe_name);
               formatted_recipe.description = i18n.t(formatted_recipe.description);
               var is_locked = formatted_recipe.level_requirement > highestLevel;
               var is_hidden = formatted_recipe.manual_unlock && !manuallyUnlockedRecipes[formatted_recipe.recipe_key] ? true : false;
               if(is_hidden == false){
                     category_has_visible_recipes = true;
               }
               Ember.set(formatted_recipe, 'is_hidden', is_hidden);
               Ember.set(formatted_recipe, 'is_locked', is_locked || is_hidden);
   
               formatted_recipe.hasWorkshop = formatted_recipe.workshop != null;
               var formatted_workshop = {};
               if (formatted_recipe.hasWorkshop) {
                  formatted_workshop.uri = formatted_recipe.workshop;
                  var catalogData = App.catalog.getCatalogData(formatted_workshop.uri);
                  if (catalogData) {
                     formatted_workshop.equivalents = catalogData.workshop_equivalents;
                  }
                  formatted_recipe.workshop = formatted_workshop;
               }
   
               formatted_recipe.is_craftable = self._areRequirementsMet(formatted_recipe, highestLevel) ? 1 : 0;
               formatted_recipe.category = category_id;
               
               recipe_array.push(formatted_recipe);
               self.allRecipes[formatted_recipe.recipe_key] = formatted_recipe;
            });
   
            if (recipe_array.length > 0 && category_has_visible_recipes) {
               //For each of the recipes inside each category, sort them by their level_requirement
               recipe_array.sort(self._compareByLevelAndAlphabetical);

               var categoryMembers = [];
               memberArray.forEach(function(member) {
                  var categoryMember = {
                     id: member.id,
                     name: member.name,
                     level: member.level,
                     disabled: member.disabledCategories[category_id] || false,
                  };
                  categoryMembers.push(categoryMember);
                  member.categoryMembers[category_id] = categoryMember;
               });
               
               var ui_category = {
                  category: category.name,
                  category_id: category_id,
                  ordinal:  category.ordinal,
                  recipes:  recipe_array,
                  members: categoryMembers,
               };
               recipe_categories.push(ui_category)
            }
         });
   
         //Sort the recipe categories by ordinal
         recipe_categories.sort(this._compareByOrdinal);
   
         //The current recipe may have been oblivated by the change in recipes. If so, set it to null.
         //If not, set it back to its (potentially new) self
         if (this.currentRecipe && this.allRecipes[this.currentRecipe.recipe_key]) {
            this.set('currentRecipe', this._getOrCalculateRecipeData(this.currentRecipe.recipe_key));
         } else {
            self.set('currentRecipe', null);
         }
   
         self.set('recipes', recipe_categories);
      }.observes('model.recipe_list', 'model.members'),

      _updateSelectedWorkshopEntity: function(e, showSelectedWorkshopCrafting) {
         var self = this;
         
         if (!e) {
            e = App.workshopManager.selectedWorkshopEntity;
         }

         var uri = e && e.uri;
         var recipes = self.get('recipes');
         radiant.each(recipes, function(_, recipeCategory) {
            radiant.each(recipeCategory.recipes, function(_, recipe) {
               var isWorkshopSelected = false;
               if (showSelectedWorkshopCrafting == true) {
                  isWorkshopSelected = !recipe.workshop;
                  if (recipe.workshop && uri) {
                     if (recipe.workshop.uri == uri) {
                        isWorkshopSelected = true;
                     }
                     else if (recipe.workshop.equivalents) {
                        for (var i = 0; i < recipe.workshop.equivalents.length; i++) {
                           if (recipe.workshop.equivalents[i] == uri) {
                              isWorkshopSelected = true;
                              break;
                           }
                        }
                     }
                  }
               }
               if (recipe.is_workshop_selected != isWorkshopSelected) {
                  Ember.set(recipe, 'is_workshop_selected', isWorkshopSelected);
               }
            });
         });
      }.observes('recipes'),

      _updateCraftSearchChecks: function(checks) {
         var self = this;

         if (checks != null) {
            var setVals = {
               Title: false,
               Description: false,
               Ingredients: false,
            };
            var chks = checks.split('|');
            chks.forEach(chk => {
               var caseStr = chk.charAt(0).toUpperCase() + chk.substr(1).toLowerCase();
               setVals[caseStr] = true;
            });

            radiant.each(setVals, function(chk, val) {
               var chkStr = 'search' + chk;
               self.set(chkStr, val);
               self.$('#' + chkStr + 'Checkbox').prop('checked', val);
            });
         }
      },

      _updateCraftInsertShown: function(div) {
         var self = this;

         if (self.SHIFT_KEY_ACTIVE && (self.HOVERING_CRAFT_BUTTON || self.HOVERING_ITEM)) {
            div.show();
         }
         else {
            div.hide();
         }
      },

      _addExtraCraftOrderConditions: function(recipe, condition) {
         var self = this;

         condition.prefer_high_quality = self.get('prefer_high_quality');
         if (self.SHIFT_KEY_ACTIVE) {
            condition.order_index = 1;
         }
      },

      _setRadioButtons: function (remaining, maintainNumber) {
         var self = this;
         self._super(remaining, maintainNumber);

         self._updateCraftOrderPreference();
      },

      _updateCraftOrderPreference: function() {
         var self = this;
         
         stonehearth_ace.getModConfigSetting('stonehearth_ace', 'default_craft_order_prefer_high_quality', function(value) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self.set('prefer_high_quality', value);
         });
      },

      // override this function since we're modifying the dynamic tooltip code
      _calculateEquipmentData: function (recipe) {
         var self = this;
         var productCatalogData = App.catalog.getCatalogData(recipe.product_uri);
   
         if (productCatalogData && (productCatalogData.equipment_required_level || productCatalogData.equipment_roles || productCatalogData.consumable_buffs || productCatalogData.consumable_effects || productCatalogData.consumable_after_effects)) {
            self.$('.detailsView').find('.tooltipstered').tooltipster('destroy');
            if (productCatalogData.equipment_roles) {
               var classArray = stonehearth_ace.findRelevantClassesArray(productCatalogData.equipment_roles);
               self.set('allowedClasses', classArray);
            }
            if (productCatalogData.equipment_required_level) {
               self.$('#levelRequirement').text(i18n.t('stonehearth:ui.game.unit_frame.level') + productCatalogData.equipment_required_level);
            } else {
               self.$('#levelRequirement').text('');
            }
            
            var equipmentTypes = [];
            if (productCatalogData.equipment_types) {
               equipmentTypes = stonehearth_ace.getEquipmentTypesArray(productCatalogData.equipment_types);
            }
            self.set('equipmentTypes', equipmentTypes);

            self._setBuffsByType(productCatalogData, 'consumable_buffs', 'consumableBuffs');
            self._setBuffsByType(productCatalogData, 'injected_buffs', 'injectedBuffs');
            self._setBuffsByType(productCatalogData, 'inflictable_debuffs', 'inflictableDebuffs');
            self._setBuffsByType(productCatalogData, 'consumable_effects', 'consumableEffects');
            self._setBuffsByType(productCatalogData, 'consumable_after_effects', 'consumableAfterEffects');

            App.tooltipHelper.createDynamicTooltip(self.$('#equipmentRequirements'), function () {
               var tooltipString = i18n.t('stonehearth:ui.game.unit_frame.no_requirements');
               if (productCatalogData.equipment_roles) {
                  tooltipString = i18n.t('stonehearth:ui.game.unit_frame.equipment_description',
                                          { class_list: radiant.getClassString(self.get('allowedClasses')) });
               }
               if (productCatalogData.equipment_required_level) {
                  tooltipString += i18n.t('stonehearth:ui.game.unit_frame.level_description', { level_req: productCatalogData.equipment_required_level });
               }
               if (productCatalogData.equipment_types) {
                  tooltipString += '<br>' + i18n.t('stonehearth_ace:ui.game.unit_frame.equipment_types_description',
                                                   { i18n_data: { types: stonehearth_ace.getEquipmentTypesString(self.get('equipmentTypes')) } });
               }
               return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth:ui.game.unit_frame.class_lv_title'), tooltipString));
            });

            // make tooltips for inflictable debuffs
            Ember.run.scheduleOnce('afterRender', this, function() {
               self._createBuffTooltips();
            });

            self.$('#recipeEquipmentPane').show();
         } else {
            self.$('#recipeEquipmentPane').hide();
         }
      },

      _setBuffsByType: function (data, buffType, propertyName) {
         var self = this;
         var buffs = [];
         radiant.each(data[buffType], function (_, buff) {
            if (!buff.invisible_to_player && !buff.invisible_on_crafting) {
               // only show stacks if greater than 1
               if (buff.stacks > 1) {
                  buff = radiant.shallow_copy(buff);
                  buff.hasStacks = true;
               }
               buffs.push(buff);
            }
         });
         self.set(propertyName, buffs);
      },

      _createBuffTooltips: function () {
         var self = this;

         self._createBuffTooltipsByType('consumableBuffs', 'consumable_buff');
         self._createBuffTooltipsByType('injectedBuffs', 'injected_buff');
         self._createBuffTooltipsByType('inflictableDebuffs', 'inflictable_debuff');
         self._createBuffTooltipsByType('consumableEffects', 'consumable_effect');
         self._createBuffTooltipsByType('consumableAfterEffects', 'consumable_after_effect');
      },

      _createBuffTooltipsByType: function(propertyName, tooltipName)
      {
         var self = this;
         var buffs = self.get(propertyName);
         radiant.each(buffs, function(_, buff) {
            var div = self.$('[data-id="' + buff.uri + '"]');
            if (div && div.length > 0) {
               App.guiHelper.addTooltip(div, buff.description, i18n.t('stonehearth_ace:ui.game.unit_frame.' + tooltipName) + i18n.t(buff.display_name));
            }
         });
      },

      //Called once when the model is loaded
      // ACE: override to modify search to allow searching ingredients and descriptions
      _build_workshop_ui: function() {
         var self = this;
   
         if (!self.$("#craftWindow")) {
            return;
         }
   
         self._buildOrderList();

         var orderList = self.$('#orders');
         orderList.on('scroll', function() {
            // when the user scrolls with the mouse, make sure the scroll buttons are right
            var buttons = self.$('#scrollButtons');
            var scrollTop = orderList.scrollTop();
            if (scrollTop === 0) {
               // top of list
               buttons.find('#orderListUpBtn').hide();
               buttons.find('#orderListDownBtn').show();
            } else if (scrollTop + orderList.innerHeight() >= orderList[0].scrollHeight) {
               // bottom of list
               buttons.find('#orderListUpBtn').show();
               buttons.find('#orderListDownBtn').hide();
            } else {
               buttons.find('#orderListUpBtn').show();
               buttons.find('#orderListDownBtn').show();
            }
         });

         var craftInsertDiv = self.$('#craftInsert');
         $(document).on('keyup keydown', function(e){
            self.SHIFT_KEY_ACTIVE = e.shiftKey;
            self._updateCraftInsertShown(craftInsertDiv);
         });
   
         self.$("#craftButton").hover(function() {
               $(this).find('#craftButtonLabel').fadeIn();
               self.HOVERING_CRAFT_BUTTON = true;
               self.set('insertRecipePortrait', self.get('currentRecipe.portrait'));
               self._updateCraftInsertShown(craftInsertDiv);
            }, function () {
               $(this).find('#craftButtonLabel').fadeOut();
               self.HOVERING_CRAFT_BUTTON = false;
               self._updateCraftInsertShown(craftInsertDiv);
            });

         self.$(".category").on({
            mouseenter: function() {
               var recipe = self._getOrCalculateRecipeData($(this).attr('recipe_key'));
               if (recipe) {
                  self.HOVERING_ITEM = true;
                  self.set('insertRecipePortrait', recipe.portrait);
                  self._updateCraftInsertShown(craftInsertDiv);
               }
            },
            mouseleave: function () {
               self.HOVERING_ITEM = false;
               self._updateCraftInsertShown(craftInsertDiv);
            }}, '.item');

         var tooltip = App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.title'),
            i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.description'));
         self.$('#craftButton').tooltipster({
            delay: 1000,
            content: $(tooltip)
         });

         tooltip = App.tooltipHelper.createTooltip(
            i18n.t('stonehearth_ace:ui.game.show_workshop.quality_preference.title'),
            i18n.t('stonehearth_ace:ui.game.show_workshop.quality_preference.description'));
         self.$('#qualityPreference label').tooltipster({
            delay: 1000,
            position: 'bottom',
            content: $(tooltip)
         });   
   
         // Perform filter after keyup to ensure that key has already been applied
         self.$('#searchInput').keyup(function (e) {
            var searchTitle = self.get('searchTitle');
            var searchDescription = self.get('searchDescription');
            var searchIngredients = self.get('searchIngredients');
            // if not searching for anything, just cancel
            if (!searchTitle && !searchDescription && !searchIngredients) {
               return;
            }

            var search = $(this).val().toLowerCase();
   
            if (!search || search == '') {
               self.$('.item:not(.is-hidden)').show();
               self.$('.category').show();
            } else {
               self.$('.category').show();
   
               // hide items that don't match the search
               self.$('.item:not(.is-hidden)').each(function (i, item) {
                  var el = $(item);
                  var recipeKey = el.attr('recipe_key');
   
                  if(self._recipeMatchesSearch(recipeKey, search, searchTitle, searchDescription, searchIngredients)) {
                     el.show();
                  } else {
                     el.hide();
                  }
               })
   
               self.$('.category').each(function(i, category) {
                  var el = $(category)
   
                  if (el.find('.item:visible').length > 0) {
                     el.show();
                  } else {
                     el.hide();
                  }
               })
            }
         });
         self.$('#searchInput').keyup();
         
         // when it has focus, show the extra settings
         self._timeoutID = null;
         self.$('#searchContainer').focusin(function (e) {
            self.set('showSearchSettings', true);
            if (self._timeoutID != null) {
               clearTimeout(self._timeoutID);
               self._timeoutID = null;
            }
         });
         self.$('#searchContainer').focusout(function (e) {
            if (self._timeoutID != null) {
               clearTimeout(self._timeoutID);
               self._timeoutID = null;
            }
            self._timeoutID = setTimeout(function() {
               self.set('showSearchSettings', false);
               // related target is always null for some reason, so don't bother with this
               //if (!$.contains(self.$('#searchContainer').get(0), e.relatedTarget)) {}
            }, 500);
         });

         App.guiHelper.addTooltip(self.$('#searchTitleDiv'), 'stonehearth_ace:ui.game.show_workshop.search_title_description');
         App.guiHelper.addTooltip(self.$('#searchDescriptionDiv'), 'stonehearth_ace:ui.game.show_workshop.search_description_description');
         App.guiHelper.addTooltip(self.$('#searchIngredientsDiv'), 'stonehearth_ace:ui.game.show_workshop.search_ingredients_description');

         App.tooltipHelper.createDynamicTooltip(self.$('[title]'));

         // Select the first recipe if currentRecipe isn't set.
         // Current recipe can be set by autotest before we reach this point.
         if (!this.currentRecipe) {
            this._selectFirstValidRecipe();
         }
      },

      _focusAndKeyUpSearchInput: function() {
         var self = this;
         self.$('#searchInput').focus();
         self.$('#searchInput').keyup();
      }.observes('searchTitle', 'searchDescription', 'searchIngredients'),

      _recipeMatchesSearch: function(recipeKey, search, searchTitle, searchDescription, searchIngredients) {
         var self = this;
         var recipe = self.allRecipes[recipeKey];

         if (recipe) {
            if (searchTitle && self._stringContains(recipe.display_name, search)) {
               return true;
            }
            if (searchDescription && self._stringContains(recipe.description, search)) {
               return true;
            }
            if (searchIngredients && recipe.ingredients) {
               recipe = self._getOrCalculateRecipeData(recipeKey);
               for (var i = 0; i < recipe.ingredients.length; i++) {
                  if (self._stringContains(recipe.ingredients[i].name, search)) {
                     return true;
                  }
               }
            }
         }

         return false;
      },

      _stringContains: function(str, search) {
         return str && str.toLowerCase().indexOf(search) > -1;
      },

      _updateUsableResources: function () {
         var self = this;
         var usableUris = {};
         var usableMaterials = {};
   
         var trackerData = App.workshopManager.usableItemTrackerData;
   
         for (var uri in trackerData) {
            var v = trackerData[uri];
            var num = v.count;

            if (uri == 'stonehearth:loot:gold') {
               num = 0;
               radiant.each(v.items, function (_, item) {
                  var stacksComp = item['stonehearth:stacks'];
                  if (stacksComp) {
                     num += stacksComp.stacks;
                  }
               });
            }
   
            // Update usableUris.
            usableUris[uri] = (usableUris[uri] || 0) + num;
            var canonicalUri = v.canonical_uri;
            if (canonicalUri && canonicalUri != uri) {
               usableUris[canonicalUri] = (usableUris[canonicalUri] || 0) + num;
            }
   
            // Update usableMaterials.
            // Transform the uri from emberValidKey format to normal (add back the periods), so that iconics can be searched correctly
            var inverseTranformedUri = uri.replace(/&#46;/g, '.');
            var catalogData = App.catalog.getCatalogData(inverseTranformedUri);
            if (catalogData && catalogData.materials) {
               for (var material in self._materialsToQuery) {
                  if (radiant.isMaterial(catalogData.materials, material)) {
                     usableMaterials[material] = (usableMaterials[material] || 0) + num;
                  }
               }
            }
         }
   
         self._usableUris = usableUris;
         self._usableMaterials = usableMaterials;
      },

      // Adding ingredient and workshop details to the recipe is expensive
      // so do it on demand we when we access a recipe.
      // override this function to add stacks consideration to ingredients
      _getOrCalculateRecipeData: function(recipe_key) {
         var self = this;
         var formatted_recipe = recipe_key && self.allRecipes[recipe_key];
         if (formatted_recipe && formatted_recipe.needs_ingredient_formatting) {
            var ingredients = formatted_recipe.ingredients;
            //Add ingredient images to the recipes
            formatted_recipe.ingredients = [];
            radiant.each(ingredients, function(i, ingredient) {
               var formatted_ingredient = radiant.shallow_copy(ingredient);
               if (formatted_ingredient.material) {
                  formatted_ingredient.identifier = formatted_ingredient.material;
                  formatted_ingredient.kind = 'material';
                  var formatting = App.resourceConstants.resources[ingredient.material];
                  if (formatting) {
                     formatted_ingredient.name = i18n.t(formatting.name);
                     formatted_ingredient.icon = formatting.icon;
                  } else {
                     // XXX, roll back to some generic icon
                     formatted_ingredient.name = i18n.t(ingredient.material);
                  }
               } else {
                  formatted_ingredient.identifier = formatted_ingredient.uri;
                  formatted_ingredient.kind = 'uri';

                  if (ingredient.uri) {
                     var catalog = App.catalog.getCatalogData(ingredient.uri);
                     if (catalog) {
                        formatted_ingredient.icon = catalog.icon;
                        formatted_ingredient.name = i18n.t(catalog.display_name);
                        formatted_ingredient.uri = ingredient.uri;
                     }
                  }
               }
               if (formatted_ingredient.min_stacks) {
                  formatted_ingredient.original_count = formatted_ingredient.count;
                  formatted_ingredient.count *= formatted_ingredient.min_stacks;
               }
               formatted_recipe.ingredients.push(formatted_ingredient);
            });

            // Add catalog data to workshop
            if (formatted_recipe.hasWorkshop) {
               var workshopCatalog = App.catalog.getCatalogData(formatted_recipe.workshop.uri);
               if (workshopCatalog) {
                  formatted_recipe.workshop.icon = workshopCatalog.icon;
                  formatted_recipe.workshop.name = i18n.t(workshopCatalog.display_name);
               }
            }

            delete formatted_recipe.needs_ingredient_formatting;
         }

         return formatted_recipe;
      },

      // have to override this whole function just to get rid of the >999 truncating for stacks
      _setPreviewStyling: function() {
         var self = this;
         if (!self.$()) {
            return;  // Menu already closed.
         }
         App.tooltipHelper.createDynamicTooltip(self.$('[title]'));
   
         var recipe = this.currentRecipe ? this._getOrCalculateRecipeData(this.currentRecipe.recipe_key) : null;
         if (recipe) {
            //Change styling that depends on the inventory trackers
            var requirementsMet = true;
   
            //Change the styling for the workshop requirement
            var $workshopRequirement = self.$('#requirementSection #workbench .requirementText')
   
            //By default, be green
            $workshopRequirement.removeClass('requirementsUnmet');
            $workshopRequirement.addClass('requirementsMet');
   
            //If there is no placed workshop, be red
            if (App.workshopManager.workbenchItemTrackerData && recipe.hasWorkshop) {
               var workshopData = App.workshopManager.workbenchItemTrackerData[recipe.workshop.uri]
               if (!workshopData && recipe.workshop.equivalents) {
                  for (var i = 0; i < recipe.workshop.equivalents.length; ++i) {
                     workshopData = App.workshopManager.workbenchItemTrackerData[recipe.workshop.equivalents[i]];
                     if (workshopData) {
                        break;
                     }
                  }
               }
               if (!workshopData) {
                  $workshopRequirement.removeClass('requirementsMet');
                  $workshopRequirement.addClass('requirementsUnmet');
                  requirementsMet = false;
               }
            }
   
            //Update the ingredients
            if (App.workshopManager.usableItemTrackerData) {
               self.$('.ingredient').each(function (index, ingredientDiv) {
                  var $ingredientDiv = $(ingredientDiv);
                  var ingredientData = {};
                  ingredientData.kind = $ingredientDiv.attr('data-kind');
                  ingredientData.identifier = $ingredientDiv.attr('data-identifier');
   
                  var numHave = self._findUsableCount(ingredientData);
   
                  var numRequired = parseInt($ingredientDiv.find('.numNeeded').text());
                  var $count = $ingredientDiv.find('.count');
                  if (numHave >= numRequired) {
                     $count.removeClass('requirementsUnmet');
                     $count.addClass('requirementsMet');
                  } else {
                     $count.removeClass('requirementsMet');
                     $count.addClass('requirementsUnmet');
                     requirementsMet = false;
                  }
                  if (numHave > 99999) {  // changed from 999
                     numHave = i18n.t('stonehearth:ui.game.show_workshop.too_many_symbol');
                  }
                  $ingredientDiv.find('.numHave').text(numHave);
               });

               // also update the primary product
               self.$('#productCount').html('');
               var uri = recipe.product_uri;
               if (uri) {
                  var count = self._usableUris[uri] || 0;
                  if (count > 99999) {
                     count = i18n.t('stonehearth:ui.game.show_workshop.too_many_symbol');
                  }
                  self.$('#productCount').text('(' + count + ')');
                  if (count == 0) {
                     self.$('#productCount').addClass('noProductsInInventory');
                  }
                  else {
                     self.$('#productCount').removeClass('noProductsInInventory');
                  }
               }
            }
   
            //Handle level requirements styling
            var $requirementText = self.$('#requirementSection #crafterLevel .requirementText')
            var curr_level = this.get('model.highest_level')
            if (recipe.level_requirement <= curr_level) {
               $requirementText.removeClass('requirementsUnmet');
               $requirementText.addClass('requirementsMet');
            } else {
               $requirementText.removeClass('requirementsMet');
               $requirementText.addClass('requirementsUnmet');
               requirementsMet = false;
            }
   
            self._showCraftUI(requirementsMet);
         }
      },

      // have to override this just for the stacks
      _formattedRecipeProductProperty: function (recipe, catalogDataKey, cssClassName) {
         if (!recipe.product_uri) {
            return '';  // Recipes are allowed to produce nothing (e.g. training mods).
         }

         var self = this;
         var productCatalogData = App.catalog.getCatalogData(recipe.product_uri);
         var outputHtml = "";
         
         var isSingleItem = true;
         if (recipe.produces && recipe.produces.length > 1 )
         {
            isSingleItem = false;
         }
         
         if (isSingleItem) {
            outputHtml += '<div class="stat ' + cssClassName + '">'
            //Default case - recipe only produces one item, get the stats the normal way
            if (productCatalogData) {
               var propertyValue = self._getPropertyValue(recipe.produces[0], productCatalogData, catalogDataKey);
               if (propertyValue) {
                  outputHtml +=  propertyValue;
               }
            }
            outputHtml += '</div>';
         } else {
            //Multi-item case - get the values of each product
            outputHtml += '<div class="stat ' + cssClassName + ' list">'
            var needComma = false;
            var allProductsSame = true;
            var previousProduct = null;
            var displayValue = "*";
            var numProducts = recipe.produces.length;
            
            //First, run through assuming the products are different. 
            //This constructs an output string along the way that may be wasted - simplifies the code, and this is only run once on click
            for (var i = 0; i < numProducts; i++) {
               var product = recipe.produces[i];
               if (product && product.item) {
                  var itemUri = product.item;
   
                  //check for the recipe just being multiples of the same output
                  if (previousProduct && itemUri != previousProduct) {
                     allProductsSame = false;
                  }
                  previousProduct = itemUri;
                  
                  //Assemble a string of the style "10, 5, 3" 
                  var itemData = App.catalog.getCatalogData(itemUri);
                  if (itemData) {
                     if (needComma) {
                        outputHtml += ', ';
                     }
                     needComma = true;
                     var propertyValue = self._getPropertyValue(product, itemData, catalogDataKey);
                     if (typeof propertyValue == "number") {
                        displayValue = propertyValue;
                     } else {
                        displayValue = "*";
                     }
                     outputHtml += displayValue;
                  }
               }
            }
            outputHtml += '</div>';
            
            //If all of the outputs were the same, then forget the string we just built and make a shorter, nicer-looking one
            if (allProductsSame) {
               outputHtml = '<div class="stat ' + cssClassName + ' mult">' + displayValue + " (x" + numProducts + ")</div>";
            }
         }
         return outputHtml;
      },

      preview: function() {
         var self = this;
         var recipe = this._getOrCalculateRecipeData(this.currentRecipe.recipe_key);
   
         if (recipe) {
            //stats
            var productCatalogData = App.catalog.getCatalogData(recipe.product_uri);
            var statHtml = '';
   
            if (productCatalogData)
            {
               statHtml = self._addStats(recipe, productCatalogData);
            }
   
            //handle the effort bubble - this is unique b/c it's on the recipe and not the recipe items
            if (recipe['effort']) {
               statHtml += '<div class="stat effort">' + recipe['effort'] + "</div>"
            }
   
            self.$('#stats').html('').append($(statHtml));
            self._addStatTooltips(productCatalogData);
   
            //Add info about equippable
            self._calculateEquipmentData(recipe);
   
            //Handle workshop requirement indicator
            var $workshopRequirement = self.$('#requirementSection #workbench .requirementText')
            if (recipe.hasWorkshop) {
               $workshopRequirement.text(i18n.t('stonehearth:ui.game.show_workshop.workshop_required') + recipe.workshop.name)
            } else {
               $workshopRequirement.text(i18n.t('stonehearth:ui.game.show_workshop.workshop_none_required'))
            }
   
            //level requirement indicator text
            var $requirementText = self.$('#requirementSection #crafterLevel .requirementText')
            if (recipe.level_requirement && recipe.level_requirement > 1) {
               $requirementText.text(
                  i18n.t('stonehearth:ui.game.show_workshop.level_requirement_needed') +
                  i18n.t(self.get('model.class_name')) +
                  i18n.t('stonehearth:ui.game.show_workshop.level_requirement_level') +
                  recipe.level_requirement)
            } else {
               $requirementText.text(i18n.t('stonehearth:ui.game.show_workshop.level_requirement_none'))
            }
         }
      },

      _addStats: function(recipe, catalogData) {
         var self = this;
         var statHtml = '';

         if (catalogData['combat_damage']) {
            statHtml += '<div class="stat damage">' + catalogData['combat_damage'] + '<br><span class=name>' + i18n.t('stonehearth:ui.game.show_workshop.damage_stat') + '</span></div>';
         }
         if (catalogData['combat_armor']) {
            statHtml += '<div class="stat armor">' + catalogData['combat_armor'] + '<br><span class=name>' + i18n.t('stonehearth:ui.game.show_workshop.armor_stat') + '</span></div>';
         }
         if (catalogData['net_worth']) {
            statHtml += self._formattedRecipeProductProperty(recipe, 'net_worth', 'netWorth');
         }
         if (catalogData['appeal']) {
            statHtml += self._formattedRecipeProductProperty(recipe, 'appeal', 'appeal');
         }
         if (catalogData['food_satisfaction']) {
            var level = self._getSatisfactionLevel(App.constants.food_satisfaction_thresholds, catalogData['food_satisfaction']);
            statHtml += self._formattedRecipeProductProperty(recipe, 'food_servings', 'satisfaction food ' + level);
            //statHtml += `<div class="stat satisfaction">${catalogData['food_servings']} x <img class="food_${level}"/></div>`;
         }
         if (catalogData['drink_satisfaction']) {
            var level = self._getSatisfactionLevel(App.constants.drink_satisfaction_thresholds, catalogData['drink_satisfaction']);
            statHtml += self._formattedRecipeProductProperty(recipe, 'drink_servings', 'satisfaction drink ' + level);
            //statHtml += `<div class="stat satisfaction">${catalogData['drink_servings']} x <img class="drink_${level}"/></div>`;
         }

         return statHtml;
      },

      _addStatTooltips: function(catalogData) {
         var self = this;

         App.tooltipHelper.createDynamicTooltip(self.$('.stat.appeal'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_appeal_stat'); });
         App.tooltipHelper.createDynamicTooltip(self.$('.stat.netWorth'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_net_worth_stat'); });
         App.tooltipHelper.createDynamicTooltip(self.$('.stat.effort'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_effort_stat'); });
         
         var satisfactionLevel;
         var servings;
         if (catalogData) {
            App.tooltipHelper.createDynamicTooltip(self.$('.stat.satisfaction'), function () {
               if (satisfactionLevel == null || servings == null) {
                  if (catalogData['food_satisfaction']) {
                     satisfactionLevel = 'food.' + self._getSatisfactionLevel(App.constants.food_satisfaction_thresholds, catalogData['food_satisfaction']);
                     servings = catalogData['food_servings'];
                  }
                  else if (catalogData['drink_satisfaction']) {
                     satisfactionLevel = 'drink.' + self._getSatisfactionLevel(App.constants.drink_satisfaction_thresholds, catalogData['drink_satisfaction']);
                     servings = catalogData['drink_servings'];
                  }
               }

               if (satisfactionLevel && servings) {
                  return i18n.t(`stonehearth_ace:ui.game.unit_frame.satisfaction.${satisfactionLevel}`, {servings: servings});
               }
            })
         }
      },

      _getSatisfactionLevel: function(thresholds, val) {
         if (val >= thresholds.HIGH) {
            return 'high';
         }
         else if (val >= thresholds.AVERAGE) {
            return 'average';
         }
         else {
            return 'low';
         }
      },

      _getPropertyValue: function (product, catalogData, key) {
         var propertyValue = catalogData[key];
         var displayValue = propertyValue;
         if (key == 'net_worth' && product && product.stacks) {
            displayValue = propertyValue * product.stacks;
         }
         return displayValue;
      },

      //Sort the recipies first by their level requirement, *then by ordinal*, and finally by their user visible name
      _compareByLevelAndAlphabetical: function(a, b) {
         if (a.level_requirement < b.level_requirement) {
            return -1;
         }
         if (a.level_requirement > b.level_requirement) {
            return 1;
         }

         // also list any with ordinals specified before any without
         if (a.ordinal != null) {
            if (b.ordinal == null) {
               return -1;
            }
            else if (a.ordinal < b.ordinal) {
               return -1;
            }
            else if (a.ordinal > b.ordinal) {
               return 1;
            }
         }
         else if (b.ordinal != null) {
            return 1;
         }

         if (a.display_name < b.display_name) {
            return -1;
         }
         if (a.display_name > b.display_name) {
            return 1;
         }
         return 0;
      },

      actions: {
         craft: function () {
            var self = this;
   
            if (self.$('#craftButtonLabel').hasClass('disabled')) {
               // TODO: play a error sound here?
               return;
            }
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:confirm'} );
            var recipe = this._getOrCalculateRecipeData(this.currentRecipe.recipe_key);
   
            var condition;
            var type = self.$('input[name=' + self.get('orderTypeName') + ']:checked').val();
            if (type == "maintain") {
               condition = {
                  type: "maintain",
                  at_least: App.stonehearth.validator.enforceNumRange(self.$('#maintainNumSelector')),
               };
            } else {
               condition = {
                  type: "make",
                  amount: App.stonehearth.validator.enforceNumRange(self.$('#makeNumSelector')),
               };
            }

            // now add the ACE options
            self._addExtraCraftOrderConditions(recipe, condition);

            console.log('craft', recipe, condition)
            radiant.call_obj(this.getOrderList(), 'add_order_command', recipe, condition)
         }
      },

      preferHighQualityId: function () { return this.get('uri').replace(/\W/g, '') + '-quality'; }.property('uri'),

      searchTitleCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-title'; }.property('uri'),

      searchDescriptionCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-description'; }.property('uri'),

      searchIngredientsCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-ingredients'; }.property('uri')
   });
});
