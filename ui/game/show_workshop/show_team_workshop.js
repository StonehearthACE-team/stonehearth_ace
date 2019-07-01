$(top).on('stonehearthReady', function() {
   // Create a proxy for the workshops object, so we know when a new StonehearthTeamCrafterView is created
   // and can then update it with our own logic.
   App.workshopManager.ace_workshops = App.workshopManager.workshops;
   App.workshopManager.workshops = new Proxy(App.workshopManager.ace_workshops, {
      get: function(target, prop) {
         return Reflect.get(target, prop);
      },
      set: function(target, prop, val) {
         App.workshopManager._ace_updateTeamCrafterView(val);
         return Reflect.set(target, prop, val);
      }
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

   App.workshopManager._ace_updateTeamCrafterView = function(teamCrafterView) {
      teamCrafterView.reopen({
         SHIFT_KEY_ACTIVE: false,

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

            var craftInsertDiv = self.$('#craftInsert');
            $(document).on('keyup keydown', function(e){
               self.SHIFT_KEY_ACTIVE = e.shiftKey;
               self._updateCraftInsertShown(craftInsertDiv);
            });

            $('#craftButton').hover(
               function() {
                  self.HOVERING_CRAFT_BUTTON = true;
                  self._updateCraftInsertShown(craftInsertDiv);
               },
               function() {
                  self.HOVERING_CRAFT_BUTTON = false;
                  self._updateCraftInsertShown(craftInsertDiv);
               }
            );
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
            self.$('#qualityPreference').tooltipster({
               delay: 1000,
               content: $(tooltip)
            });

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

            self._updateCraftOrderPreference();
         },

         _updateCraftInsertShown: function(div) {
            var self = this;

            if (self.SHIFT_KEY_ACTIVE && self.HOVERING_CRAFT_BUTTON) {
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
            
            radiant.call('radiant:get_config', 'mods.stonehearth_ace.default_craft_order_prefer_high_quality')
            .done(function(o) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               var prefer_high_quality = o['mods.stonehearth_ace.default_craft_order_prefer_high_quality'];
               if (prefer_high_quality != false) {
                  prefer_high_quality = true;
               }
               self.set('prefer_high_quality', prefer_high_quality);
            });
         },

         // override this function since we're modifying the dynamic tooltip code
         _calculateEquipmentData: function (recipe) {
            var self = this;
            var productCatalogData = App.catalog.getCatalogData(recipe.product_uri);
      
            if (productCatalogData && (productCatalogData.equipment_required_level || productCatalogData.equipment_roles || productCatalogData.consumable_buffs)) {
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

               var consumableBuffs = [];
               radiant.each(productCatalogData.consumable_buffs, function (_, buff) {
                  if (!buff.invisible_to_player && !buff.invisible_on_crafting) {
                     // only show stacks if greater than 1
                     if (buff.stacks > 1) {
                        buff = radiant.shallow_copy(buff);
                        buff.hasStacks = true;
                     }
                     consumableBuffs.push(buff);
                  }
               });
               self.set('consumableBuffs', consumableBuffs);

               var injectedBuffs = [];
               radiant.each(productCatalogData.injected_buffs, function (_, buff) {
                  if (!buff.invisible_to_player && !buff.invisible_on_crafting) {
                     // only show stacks if greater than 1
                     if (buff.stacks > 1) {
                        buff = radiant.shallow_copy(buff);
                        buff.hasStacks = true;
                     }
                     injectedBuffs.push(buff);
                  }
               });
               self.set('injectedBuffs', injectedBuffs);

               var inflictableDebuffs = [];
               radiant.each(productCatalogData.inflictable_debuffs, function (_, debuff) {
                  if (!debuff.invisible_to_player && !debuff.invisible_on_crafting) {
                     // only show stacks if greater than 1
                     if (debuff.stacks > 1) {
                        debuff = radiant.shallow_copy(debuff);
                        debuff.hasStacks = true;
                     }
                     inflictableDebuffs.push(debuff);
                  }
               });
               self.set('inflictableDebuffs', inflictableDebuffs);
      
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

         _createBuffTooltips: function () {
            var self = this;

            var consumableBuffs = self.get('consumableBuffs');
            radiant.each(consumableBuffs, function(_, buff) {
               var div = self.$('[data-id="' + buff.uri + '"]');
               if (div.length > 0) {
                  App.guiHelper.addTooltip(div, buff.description, i18n.t('stonehearth_ace:ui.game.unit_frame.consumable_buff') + i18n.t(buff.display_name));
               }
            });

            var injectedBuffs = self.get('injectedBuffs');
            radiant.each(injectedBuffs, function(_, buff) {
               var div = self.$('[data-id="' + buff.uri + '"]');
               if (div.length > 0) {
                  App.guiHelper.addTooltip(div, buff.description, i18n.t('stonehearth_ace:ui.game.unit_frame.injected_buff') + i18n.t(buff.display_name));
               }
            });

            var inflictableDebuffs = self.get('inflictableDebuffs');
            radiant.each(inflictableDebuffs, function(_, debuff) {
               var div = self.$('[data-id="' + debuff.uri + '"]');
               if (div.length > 0) {
                  App.guiHelper.addTooltip(div, debuff.description, i18n.t('stonehearth_ace:ui.game.unit_frame.inflictable_debuff') + i18n.t(debuff.display_name));
               }
            });
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
                     num += item['stonehearth:stacks'].stacks;
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
               var propertyValue = self._getPropertyValue(recipe.produces[0], productCatalogData, catalogDataKey);
               if (propertyValue) {
                  outputHtml +=  propertyValue;
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

         _getPropertyValue: function (product, catalogData, key) {
            var propertyValue = catalogData[key];
            var displayValue = propertyValue;
            if (key == 'net_worth' && product && product.stacks) {
               displayValue = propertyValue * product.stacks;
            }
            return displayValue;
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

         preferHighQualityId: function () { return this.get('uri').replace(/\W/g, '') + '-quality'; }.property('uri')
      });
   };
});
