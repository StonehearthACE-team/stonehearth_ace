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
      
            if (productCatalogData && (productCatalogData.equipment_required_level || productCatalogData.equipment_roles)) {
               self.$('.detailsView').find('.tooltipstered').tooltipster('destroy');
               if (productCatalogData.equipment_roles) {
                  var classArray = radiant.findRelevantClassesArray(productCatalogData.equipment_roles);
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
      
               App.tooltipHelper.createDynamicTooltip(self.$('#recipeEquipmentPane'), function () {
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

               self.$('#recipeEquipmentPane').show();
            } else {
               self.$('#recipeEquipmentPane').hide();
            }
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
