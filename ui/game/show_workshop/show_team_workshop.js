var _showSelectedWorkshopCrafting = false;
var _craftSearchChecks = null;

App.workshopManager = {
   workshops: {},

   workbenchItemTracker: null,
   workbenchItemTrackerTrace: null,
   workbenchItemTrackerData: {},

   usableItemTracker: null,
   usableItemTrackerTrace: null,
   usableItemTrackerData: {},

   notifyItemsChanged: $.throttle(500, function () { $(App.workshopManager).trigger('itemsChanged'); }),

   init: function () {
      var self = this;

      // Workbenches are tracked always, since that's super cheap, and reduces workshop UI startup time.
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:workbench_item_tracker')
         .done(function (response) {
            self.workbenchItemTracker = response.tracker;
            self.workbenchItemTrackerTrace = new StonehearthDataTrace(self.workbenchItemTracker, {
                  'tracking_data': {
                     '*': {
                        'items': {
                           '*': {
                              'stonehearth:workshop': {},
                              'stonehearth_ace:auto_craft': {}
                           }
                        }
                     }
                  }
               })
               .progress(function (response) {
                  self.workbenchItemTrackerData = response.tracking_data;
                  self.notifyItemsChanged();
               });
         });

      // Items are only tracked while a workshop is open, but we keep the last known value to hide the workshop startup time.
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:usable_item_tracker')
         .done(function (response) {
            self.usableItemTracker = response.tracker;
            self.pauseOrResumeTrackingItems();
         });
   },

   // ACE: also track gold stacks for gold coin crafting
   pauseOrResumeTrackingItems: $.debounce(1, function () {
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
   }),

   createWorkshop: function (jobAlias, show, cb) {
      var self = this;
      if (self.workshops[jobAlias]) return;

      radiant.call_obj('stonehearth.job', 'get_job_call', jobAlias)
         .done(function (response) {
            if (self.workshops[jobAlias]) return;
            if (response.job_info_object) {
               self.workshops[jobAlias] = App.stonehearth.showTeamWorkshopView = App.gameView.addView(
                     App.StonehearthTeamCrafterView, { uri: response.job_info_object });
               if (show || cb) {
                  var workshop = self.workshops[jobAlias];
                  $(workshop).on('recipesInitialized', function () {
                     $(workshop).off('recipesInitialized');
                     if (show) {
                        workshop.show(true);
                     }
                     if (cb) {
                        cb(workshop);
                     }
                  });
               }
            }
         });
   },

   toggleWorkshop: function (jobAlias) {
      var self = this;

      // Hide all other workshops.
      var hidOther = false;
      radiant.each(self.workshops, function (alias, view) {
         if (alias != jobAlias && view.isVisible) {
            view.hide(false);
            hidOther = true;
         }
      });

      if (self.workshops[jobAlias]) {
         // This workshop exists, just toggle it.
         if (self.workshops[jobAlias].isVisible) {
            self.workshops[jobAlias].hide(true);
         } else {
            self.workshops[jobAlias].show(!hidOther);
         }
      } else {
         // First time opening the workshop. Instantiate it. Should generally never happen, but there in case of mod-induced races.
         self.createWorkshop(jobAlias, true);
      }
   },

   // pass in a callback function in case the workshop is not yet loaded
   getWorkshop: function (jobAlias, cb) {
      var self = this;
      if (self.workshops[jobAlias] && cb) {
         cb(self.workshops[jobAlias]);
      } else {
         self.createWorkshop(jobAlias, false, cb);
      }

      return self.workshops[jobAlias];
   },

   getWorkshopByOrderList: function (orderList) {
      var self = this;
      return _.find(self.workshops, function (w) {
         return w.getOrderList() == orderList;
      });
   },
};

App.StonehearthTeamCrafterView = App.View.extend({
   templateName : 'stonehearthTeamCrafter',
   uriProperty: 'model',
   closeOnEsc: true,
   skipInvisibleUpdates: true,
   components: {
      "order_list" : {
         "orders" : {
            "associated_orders" : {
               "*": {},
            },
            "curr_crafters" : {},
            "recipe" : {},
         },
         "secondary_orders" : {
            "associated_orders" : {
               "*": {},
            },
            "curr_crafters" : {},
            "recipe" : {},
         },
         "auto_craft_orders" : {
            "associated_orders" : {
               "*": {},
            },
            "curr_crafters" : {},
            "recipe" : {},
         },
      },
      "recipe_list" : {
         "*": {
            "recipes": {
               "*": {
                  "recipe": {},
               },
            },
         },
      },
      // ACE: track the individual crafters that are part of this crafting view
      "members": {
         "*": {
            'stonehearth:job': {},
            "stonehearth:unit_info": {},
         },
      },
   },

   currentRecipe: null,
   isPaused: false,
   isSecondaryListPaused: false,
   queueAnywayStatus: false,
   maxActiveOrders: 30,
   scrollAmount: 78,
   craft_button_text: 'stonehearth:ui.game.show_workshop.craft',
   highlightedOrders: [],

   makeSortable: function(element, args) {
      if (element) {
         if (args == 'destroy' && !element.is('.ui-sortable')) {
            return;
         }
         return element.sortable(args);
      }
   },

   dismiss: function (pressedEsc) {
      // if the player pressed escape to close the window, check if we should instead close interaction divs
      if (pressedEsc && this._destroyModifyOrderDiv()) {
         return true;
      }
      this.hide(true);
   },

   show: function (animate) {
      var self = this;
      if (animate) {
         self._super();
         self.$("#craftWindow").animate({ top: 0 }, 350, 'easeOutBounce', function () {
            App.workshopManager.pauseOrResumeTrackingItems();
         });
      } else {
         self.$("#craftWindow").css('top', 0);
         self._super();
         App.workshopManager.pauseOrResumeTrackingItems();
      }
      App.stonehearth.modalStack.push(this);
      App.workshopManager.notifyItemsChanged();

      var sound = self.get('model.open_sound');
      if (sound) {
         radiant.call('radiant:play_sound', { 'track': sound });
      }
   },

   hide: function (animate) {
      var self = this;

      if (!self.$()) return;

      var doHide = function () {
         var index = App.stonehearth.modalStack.indexOf(self)
         if (index != -1) {
            App.stonehearth.modalStack.splice(index, 1);
         }
         App.View.prototype.hide.call(self);
         App.workshopManager.pauseOrResumeTrackingItems();
      }

      if (animate && self.$("#craftWindow")) {
         var sound = self.get('model.close_sound');
         if (sound) {
            radiant.call('radiant:play_sound', { 'track': sound });
         }
         self.$("#craftWindow").animate({ top: -1000 }, 250, 'easeOutBounce', function () {
            doHide();
         });
      } else {
         self.$("#craftWindow").css('top', -1000);
         doHide();
      }
   },

   _reactToVisibilityChanged: function () {
      var self = this;
      self._super();
      if (self.get('isVisible')) {
         self._onOrdersUpdated();
         self._onSecondaryOrdersUpdated();
         self._onOrderCountUpdated();
      }
      else {
         self._destroyModifyOrderDiv();
         self.$('.tooltipstered').tooltipster('hide');
      }
   }.observes('isVisible'),

   // ACE: added lots of features
   didInsertElement: function() {
      var self = this;
      self._super();

      self._usableUris = {};
      self._usableMaterials = {};
      self._orderRecipeMap = {};

      self.$('#searchInput').attr('placeholder', i18n.t('stonehearth:ui.game.show_workshop.placeholder'));
      self.$('#recipeTab').show();

      self.set('maxActiveOrders', App.constants.crafting.DEFAULT_MAX_CRAFT_ORDERS);

      radiant.call('radiant:get_config', 'mods.stonehearth.max_crafter_orders')
         .done(function(response) {
            var maxCrafterOrders = response['mods.stonehearth.max_crafter_orders'];
            if (maxCrafterOrders) {
               self.set('maxActiveOrders', maxCrafterOrders);
            }
         })

      $(App.workshopManager).on('itemsChanged', function () {
         if (self.isVisible) {
            self._updateUsableResources();
            self._updateFullDetailedOrderList();
            self._updateCraftableRecipes();
            self._setPreviewStyling();
         }
      });
      App.workshopManager.notifyItemsChanged();

      self.$().on( 'click', '.craftNumericButton', function() {
         var button = $(this);
         var inputControl = button.parent().find('input');
         var oldValue = parseInt(inputControl.val());

         if (inputControl.prop('disabled')) {
            return;
         }

         if (button.text() == "-") {
            //trying to make as many as possible
            var inputMin = parseInt(inputControl.attr('min'));
            if (oldValue <= inputMin) {

               var allIngredients = self.$('.detailsView #ingredients .ingredient .requirementsMet');
               if (allIngredients && allIngredients.length > 0) {
                  var ingredientCount = allIngredients.length;
                  var maxOrdersMakeable = parseInt(inputControl.attr('max'));
                  for (var i=0; i < ingredientCount; ++i) {
                     var currentIngredient = $(allIngredients[i]);
                     var have = parseInt(currentIngredient.find('.numHave').html());
                     var required = parseInt(currentIngredient.find('.numNeeded').html());
                     var maxProduceable = Math.floor(have/required);
                     if (maxProduceable < maxOrdersMakeable) {
                        maxOrdersMakeable = maxProduceable;
                     }
                  }
               }
               if (maxOrdersMakeable > 0) {
                  // Note we plus 1 here because clicking on the - button will also subtract one from the number
                  // That listener is in input.js and we are basically trying to compete with it.
                  inputControl.val(maxOrdersMakeable + 1).change();
               }
            }
         }
      });

      //Craft or maintain on click/ctrl+click of right mouse button.
      // ACE: incorporate the ability to specify the position of the order.
      self.$('#recipeItems').off('mousedown.craftOrMaintain', '.item');
      self.$('#recipeItems').on('mousedown.craftOrMaintain', '.item', function (e) {
         var orderArgs;
         if (e.button == 2) {
            if (e.ctrlKey) {
               orderArgs = { type: "maintain", at_least: 1, quick_add: true };
            } else {
               orderArgs = { type: "make", amount: 1, quick_add: true};
            }
            if (e.shiftKey) {
               orderArgs.order_index = 1;
            }
         }
         if (orderArgs) {
            var recipe = self._getOrCalculateRecipeData($(this).attr('recipe_key'));
            if (recipe.is_auto_craft && orderArgs.type == 'make') {
               // can't queue auto-craft as make, only as maintain
               orderArgs = { type: "maintain", at_least: orderArgs.amount, quick_add: true };
            }
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
      // ACE: incorporate the ability to also remove associated orders.
      self.$('.orders').off('mousedown.existingOrderClick', '.orderListItem');
      self.$('.orders').on('mousedown.existingOrderClick', '.orderListItem', function (e) {
         if (e.button == 2) {
            var orderList = self.getOrderList();
            var item = $(this);
            var orderId = parseInt(item.attr("data-orderid"));
            var deleteAssociatedOrders = stonehearth_ace.isShiftKeyActive();
            radiant.call_obj(orderList, 'delete_order_command', orderId, deleteAssociatedOrders)
               .done(function(return_data){
                  item.remove();
                  if (return_data && return_data.associated_orders) {
                     radiant.each(return_data.associated_orders, function(_, order_id) {
                        self.$('.orders').find("[data-orderid='"+order_id+"']").remove();
                     })
                  }
                  radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash'} );
               });
         }
      });

      self.$('.orders').off('mouseenter.existingOrderEnter', '.interactionOverlay');
      self.$('.orders').on('mouseenter.existingOrderEnter', '.interactionOverlay', function (e) {
         var $el = $(this).closest('.orderListItem');
         var orderId = parseInt($el.attr("data-orderid"));
         var order;

         var isPrimaryOrderList = $el.closest('.orders').attr('id') == 'orders';
         var primaryOrders = self.get('model.order_list.orders') || [];
         var orderList = (primaryOrders).concat(self.get('model.order_list.secondary_orders') || []).concat(self.get('model.order_list.auto_craft_orders') || []);
         radiant.each(orderList, function(_, o) {
            if (o.id == orderId) {
               order = o;
               return false;
            }
         });

         self.highlightType = null;
         self.childOrders = null;
         if (order) {
            var olRef = self.getOrderList();
            if (order.associated_orders && order.associated_orders.length > 0) {
               // consider all the associated orders with parents (and thus could be descendents of this order)
               // orders can be part of other jobs' order lists, so their id on its own is not unique!
               var allParentOrders = [];
               radiant.each(order.associated_orders, function(_, o) {
                  if (o.parent_order) {
                     allParentOrders.push(o);
                  }
               });

               // keep going through all the possible descendents, including any with a valid parent and marking those for the next iteration
               var orders = [];
               var parents = [];
               var newParents = [{id: order.id, order_list: olRef}];
               while (newParents.length > 0) {
                  var newNewParents = [];
                  for (var i = 0; i < allParentOrders.length; i++) {
                     var o = allParentOrders[i];
                     for (var j = 0; j < newParents.length; j++) {
                        if (newParents[j].id == o.parent_order.id && newParents[j].order_list == o.parent_order.order_list) {
                           orders.push({order: o.order, isLocal: o.order.order_list == olRef});
                           newNewParents.push({id: o.order.id, order_list: o.order.order_list});
                           break;
                        }
                     }
                  }

                  parents.push(...newParents);
                  newParents = newNewParents;
               }

               orders.sort((a, b) => b.isLocal - a.isLocal);
               self.childOrders = orders;
               self.highlightedOrders = orders;

               self.highlightType = 'craftHighlighted';
            }

            // if it has a building id, highlight all orders for that building (locked to primary order list)
            // if this order has associated orders, highlight only the direct children (the orders that will be removed if this one is removed)
            if (order.building_id) {
               self.highlightedOrders = [];
               radiant.each(orderList, function(_, o) {
                  if (o.building_id == order.building_id && o.order_list == olRef) {
                     self.highlightedOrders.push({order: o, isLocal: true});
                  }
               });
               self.highlightType = 'buildingHighlighted';
            }
         }

         self._updateFullDetailedOrderList();

         // show the tooltip for the order
         if (order) {
            self._showCraftOrderTooltip($el, order, isPrimaryOrderList || primaryOrders.length == 0);
         }
      });

      self.$('.orders').off('mouseleave.existingOrderLeave', '.interactionOverlay');
      self.$('.orders').on('mouseleave.existingOrderLeave', '.interactionOverlay', function (e) {
         self.highlightedOrders = {};
         self._updateFullDetailedOrderList();
      });

      self.$('.orders').off('dblclick.existingOrderDblClick', '.orderListItem');
      self.$('.orders').on('dblclick.existingOrderDblClick', '.orderListItem', function (e) {
         self._setupModifyOrder($(this));
      });

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

      self.$('#allCrafters').on('click', '.categoryCrafter', function() {
         var $elem = $(this);
         var id = $elem.attr('crafterId');

         var member = self._memberLookup[id];
         if (member) {
            var enable = false;
            var categories = [];
            radiant.each(member.categoryMembers, function(category, categoryMember) {
               if (categoryMember.disabled) {
                  enable = true;
               }
               categories.push(category);
            });
            radiant.call('stonehearth_ace:set_crafting_categories_disabled', member.objectRef, categories, !enable);

            // also update the status so it toggles the class on the element
            radiant.each(member.categoryMembers, function(category, categoryMember) {
               Ember.set(categoryMember, 'disabled', !enable);
               self._updateAllMembersDisabledForCategory(category);
            });
            Ember.set(member, 'categoryCraftingClass', enable ? 'enabledCrafting' : 'allDisabledCrafting');
         }
      });

      self.$('#recipeItems').on('click', '.categoryCrafter', function() {
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
               //self._updateFullDetailedOrderList();
            }

            // also update whether all members for this category are disabled
            self._updateAllMembersDisabledForCategory(category);
         }
      });

      self.hide(false);  // Hidden by default.
   },

   destroy: function() {
      if (this._playerInventoryTrace) {
         this._playerInventoryTrace.destroy();
         this._playerInventoryTrace = null;
      }
      if (this._playerUsableInventoryTrace) {
         this._playerUsableInventoryTrace.destroy();
         this._playerUsableInventoryTrace = null;
      }

      App.stonehearth.showTeamWorkshopView = null;
      this._destroyCrafterTraces();
      this._super();
   },

   willDestroyElement: function () {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');
      App.guiHelper.removeDynamicTooltip(self.$('[title]'));
      self.$('#craftButton').off('mouseenter mouseleave hover');
      self.$('#searchInput').off('keydown keyup');
      this.makeSortable(self.$('.orders, .garbageList'), 'destroy');
      this.makeSortable(self.$('#orderListContainer table'), 'destroy');
      self.$('.orders, .garbageList').enableSelection();
      self.$('#orderListContainer table').enableSelection();

      App.guiHelper.removeDynamicTooltip(self.$('#recipeItems'), '.interactionOverlay');
      App.guiHelper.removeDynamicTooltip(self.$('#craftingWindow'), '.statusSign');

      if (self.$('#recipeItems')) {
         self.$('#recipeItems').off('mousedown.craftOrMaintain', '.item');
      }
      if (self.$('.orders')) {
         self.$('.orders').off('mousedown.existingOrderClick', '.orderListItem');
      }

      self.$(".category").off('mouseenter mouseleave', '.item');
      self.$('.orders').off('scroll');
      $(document).off('keyup.show_team_workshop keydown.show_team_workshop');
      self.$('#searchSettingContainer').off('change.refocusInput', '.searchSettingCheckbox');
      self.$('#searchContainer').off('focusin');
      self.$('#searchContainer').off('focusout');
      if (self._focusCheckIntervalID != null) {
         clearInterval(self._focusCheckIntervalID);
         self._focusCheckIntervalID = null;
      }

      this._super();
   },

   _destroyCrafterTraces: function(exceptTheseCrafters) {
      var keptTraces = {};
      var tracesRemoved = false;
      if (this._crafterTraces) {
         radiant.each(this._crafterTraces, function(id, trace) {
            if (exceptTheseCrafters && exceptTheseCrafters[id] != null) {
               keptTraces[id] = trace;
            }
            else {
               trace.destroy();
               tracesRemoved = true;
            }
         });
      }
      this._crafterTraces = keptTraces;
      return tracesRemoved;
   },

   _updateAllMembersDisabledForCategory: function(category) {
      var self = this;
      var allDisabled = true;
      radiant.each(self._memberLookup, function(id, member) {
         if (member.categoryMembers[category] && !member.categoryMembers[category].disabled) {
            allDisabled = false;
            return false;
         }
      });
      var category = self.allCategories[category];
      if (category) {
         Ember.set(category, 'allMembersDisabled', allDisabled);
      }
   },

   _getOrderById: function(orderId) {
      var self = this;
      var [order, index, count] = self._getOrderFromOrderList(orderId, self.get('model.order_list.orders'));

      if (!order) {
         [order, index, count] = self._getOrderFromOrderList(orderId, self.get('model.order_list.secondary_orders'));
      }

      if (!order) {
         [order, index, count] = self._getOrderFromOrderList(orderId, self.get('model.order_list.auto_craft_orders'));
      }

      return [order, index, count];
   },

   _getOrderFromOrderList: function(orderId, orderList) {
      var order;
      var index = 1;
      radiant.each(orderList, function(_, o) {
         if (o.id == orderId) {
            order = o;
            return false;
         }
         else if (!order) {
            index++;
         }
      });
      return [order, index, orderList.length];
   },

   _destroyModifyOrderDiv: function() {
      var self = this;
      self._isModifyingOrder = false;
      var modifyDif = self.$().find('.modifyOrder');
      if (modifyDif.length > 0) {
         modifyDif.find('.tooltipstered').tooltipster('destroy')
         modifyDif.remove();
         return true;
      }
   },

   _setupModifyOrder: function ($el) {
      // <input class="modifyOrderAmount" type="number" value="1" min="1" max="99">
      // <img class="moveOrderToTopBtn"/>
      // <img class="moveOrderToTopBottom"/>
      // <img class="moveOrderToPrimaryList"/>
      // <img class="moveOrderToSecondaryList"/>
      // TODO: show controls as relevant for this order
      // allow moving to top/bottom of the list for all
      // allow moving to primary/secondary list for non-building secondary/primary orders (not auto-craft)
      // allow modifying quantity for all except those with building ids
      var self = this;
      var orderId = $el.data('orderid');
      var [order, index, count] = self._getOrderById(orderId);
      if (!order) {
         return;
      }

      // check if we're already modifying this order
      // if so, just cancel it and return
      var hasExistingModifyOrder = $el.find('.modifyOrder').length > 0;
      self._destroyModifyOrderDiv();

      if (hasExistingModifyOrder) {
         return;
      }

      var orderList = self.getOrderList();
      var isBuildingOrder = order.building_id != null;
      var isAutoCraftOrder = order.recipe.is_auto_craft;
      var isPrimaryOrderList = $el.closest('.orders').attr('id') == 'orders';
      var orderAmount = order.condition.remaining || order.condition.at_least || 1;

      var $moveToTop, $moveToBottom, $swapPriority, $modifyAmountImg, $modifyAmount;
      var $modifyDiv = $modifyDiv = $('<div class="modifyOrder">');
      var tooltipString;
      $el.append($modifyDiv);

      if (index > 1) {
         $moveToTop = $('<img class="moveOrderToTopBtn button">');
         $modifyDiv.append($moveToTop);
         $moveToTop.click(function() {
            radiant.call_obj(orderList, 'change_order_position_command', 1, orderId);
            self._destroyModifyOrderDiv();
         });

         tooltipString = App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_move_order_to_top'));
         $moveToTop.tooltipster({
            content: $(tooltipString)
         });
      }

      if (index < count) {
         $moveToBottom = $('<img class="moveOrderToBottomBtn button">');
         $modifyDiv.append($moveToBottom);
         $moveToBottom.click(function() {
            radiant.call_obj(orderList, 'change_order_position_command', -1, orderId);
            self._destroyModifyOrderDiv();
         });

         tooltipString = App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_move_order_to_bottom'));
         $moveToBottom.tooltipster({
            content: $(tooltipString)
         });
      }

      if (!isBuildingOrder) {
         if (!isAutoCraftOrder) {
            $swapPriority = $('<img class="swapOrderListPriority button">');
            if (isPrimaryOrderList) {
               $swapPriority.addClass('moveOrderToSecondaryList');
            }
            else {
               $swapPriority.addClass('moveOrderToPrimaryList');
            }
            $modifyDiv.append($swapPriority);
            $swapPriority.click(function() {
               radiant.call('stonehearth_ace:toggle_order_list_priority', self.get('model.alias'), orderId);
               self._destroyModifyOrderDiv();
            });

            tooltipString = App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.show_workshop.' +
               (isPrimaryOrderList ? 'tooltip_swap_order_priority_secondary' : 'tooltip_swap_order_priority_primary')));
            $swapPriority.tooltipster({
               content: $(tooltipString)
            });
         }

         $modifyAmountImg = $('<img class="modifyOrderAmountImg">');
         $modifyDiv.append($modifyAmountImg);

         $modifyAmount = $('<input class="modifyOrderAmount" type="number" value="' + orderAmount + '" min="1" max="99">');
         $modifyDiv.append($modifyAmount);
         $modifyAmount.keydown(function (e) {
            if (e.key == 'Escape') {
               e.stopPropagation();
            }
         });
         $modifyAmount.keyup(function (e) {
            if (e.key == 'Escape') {
               e.stopPropagation();
               self._destroyModifyOrderDiv();
            }
            else if (e.key == 'Enter') {
               var val = Math.min(99, Math.max(1, parseInt($modifyAmount.val())));
               if (val != orderAmount) {
                  radiant.call('stonehearth_ace:modify_order_amount', self.get('model.alias'), orderId, val);
               }
               self._destroyModifyOrderDiv();
            }
         });

         tooltipString = App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_modify_amount'));
         $modifyAmount.tooltipster({
            content: $(tooltipString)
         });

         // focus and select the amount
         $modifyAmount.focus();
         $modifyAmount.select();
      }

      self._isModifyingOrder = true;

      // clear out highlighted orders because the css filters mess up z-ordering
      self.$('.orderListItem').removeClass('buildingHighlighted craftHighlighted');
   },

   getOrderList: function(){
      return this.get('model.order_list').__self;
   },

   // ACE: overriding just to also put the i18n.t-ed description in
   _buildRecipeArray: function () {
      var self = this;
      if (self.isDestroying || self.isDestroyed) {
         return;
      }

      var memberArray = self._memberArray || [];
      var recipes = this.get('model.recipe_list');
      var recipe_categories = [];
      var memberEnabledCount = {};
      var totalCategories = 0;
      self.allRecipes = {};
      self.allCategories = {};

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
            // var formatted_workshop = {};
            // if (formatted_recipe.hasWorkshop) {
            //    formatted_workshop.uri = formatted_recipe.workshop;
            //    var catalogData = App.catalog.getCatalogData(formatted_workshop.uri);
            //    if (catalogData) {
            //       formatted_workshop.equivalents = catalogData.workshop_equivalents;
            //    }
            //    formatted_recipe.workshop = formatted_workshop;
            // }

            formatted_recipe.is_craftable = self._areRequirementsMet(formatted_recipe, highestLevel) ? 1 : 0;
            //formatted_recipe.category = category_id;
            
            recipe_array.push(formatted_recipe);
            self.allRecipes[formatted_recipe.recipe_key] = formatted_recipe;
         });

         if (recipe_array.length > 0 && category_has_visible_recipes) {
            totalCategories++;
            //For each of the recipes inside each category, sort them by their level_requirement
            recipe_array.sort(self._compareByLevelAndAlphabetical);

            var categoryMembers = [];
            var allDisabled = true;
            memberArray.forEach(function(member) {
               var disabled = member.disabledCategories[category_id] || false;
               if (!disabled) {
                  allDisabled = false;
               }
               var categoryMember = {
                  id: member.id,
                  name: member.name,
                  level: member.level,
                  disabled: disabled,
               };
               categoryMembers.push(categoryMember);
               member.categoryMembers[category_id] = categoryMember;
               memberEnabledCount[member.id] = (memberEnabledCount[member.id] || 0) + (disabled ? 0 : 1);
            });
            
            var ui_category = {
               category: category.name,
               category_id: category_id,
               ordinal:  category.ordinal,
               recipes:  recipe_array,
               members: categoryMembers,
               allMembersDisabled: allDisabled,
            };
            recipe_categories.push(ui_category)
            self.allCategories[category_id] = ui_category;
         }
      });

      memberArray.forEach(function(member) {
         var enabledCount = memberEnabledCount[member.id] || 0;
         var enabledClass = enabledCount == totalCategories ? 'enabledCrafting' : (enabledCount == 0 ? 'allDisabledCrafting' : 'someEnabledCrafting');
         Ember.set(member, 'categoryCraftingClass', enabledClass);
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

      if (!self._recipeListInitialized) {
         $(self).trigger('recipesInitialized');
      }
      self._recipeListInitialized = true;
   }.observes('model.recipe_list'),

   _updateMembers: function() {
      var self = this;
      var members = this.get('model.members');

      var memberLookup = self._memberLookup;
      var memberArray = self._memberArray;
      if (!memberLookup) {
         memberLookup = {};
         self._memberLookup = memberLookup;
         memberArray = [];
         self._memberArray = memberArray;
      }

      self._destroyCrafterTraces(members);

      if (members) {
         var removedMembers = {};
         radiant.each(memberLookup, function(id, member) {
            removedMembers[id] = true;
         });

         radiant.each(members, function(id, member) {
            delete removedMembers[id];

            // the individual members need to be traced to track their disabled categories
            if (self._crafterTraces[id] != null) {
               var name = member['stonehearth:unit_info'].custom_name;
               memberLookup[id].name = name;
            }
            else {
               var name = member['stonehearth:unit_info'].custom_name;

               var memberStruct = {
                  objectRef: member.__self,
                  id: id,
                  name: name,
                  level: 0,
                  disabledCategories: {},
                  categoryProficiencies: {},
                  categoryMembers: {},
                  categoryCraftingClass: 'enabledCrafting',
               };
               memberArray.push(memberStruct);
               memberLookup[id] = memberStruct;

               self._crafterTraces[id] = new StonehearthDataTrace(member['stonehearth:job'].curr_job_controller, {})
                  .progress(function (response) {
                     if (self.isDestroyed || self.isDestroying) {
                        return;
                     }
                     
                     var m = self._memberLookup[id];
                     if (m) {
                        var jobController = response;
                        if (jobController) {
                           var level = jobController.last_gained_lv;
                           var disabledCategories = jobController.disabled_crafting_categories;
                           
                           // this can be set without updating the ui because it only shows in tooltips
                           m.category_profiencies = jobController.category_profiencies;

                           // for the other fields, changing them changes the ui if they're different
                           if (level != m.level || !stonehearth_ace.shallowAreEqual(disabledCategories, m.disabledCategories)) {
                              m.level = level;
                              m.disabledCategories = disabledCategories;
                              self._membersUpdated();
                           }
                        }
                     }
                  });
            }
         });

         // removed members must be removed from the list
         var removedAny = false;
         radiant.each(removedMembers, function(id, _) {
            memberArray.removeObject(memberLookup[id]);
            delete memberLookup[id];
            removedAny = true;
         });

         // if any were removed, we need to update to get rid of their category icons
         if (removedAny) {
            self._membersUpdated();
         }
      }
   }.observes('model.members'),

   _membersUpdated: function () {
      var self = this;
      // sort first by level, then by entity id
      // they're both numeric, and 0 equates to false, so we can do it with one expression
      self._memberArray.sort((a, b) => (a.level - b.level) || (a.id - b.id));
      self.set('allMembers', self._memberArray.slice());
      self._buildRecipeArray();
      self._updateFullDetailedOrderList();

      Ember.run.scheduleOnce('afterRender', function() {
         self.$('#allCrafters .categoryCrafter').each(function() {
            var $elem = $(this);
            App.tooltipHelper.createDynamicTooltip($elem, function () {
               var id = $elem.attr('crafterId');

               var member = self._memberLookup[id];
               if (member) {
                  var data = {
                     name: member.name,
                     level: member.level,
                  };

                  var categories = [];
                  radiant.each(self.allCategories, function(category, data) {
                     categories.push({
                        category: data.category,
                        ordinal: data.ordinal,
                        proficiency: member.category_profiencies[category] || 0,
                        enabled: !member.categoryMembers[category].disabled,
                     });
                  });
                  categories.sort(self._compareByOrdinal);

                  // TODO: say current status (no/some/all categories enabled); what clicking will do; list all category proficiencies for this member
                  // change these tooltips to have the crafter name as the title and then clear/bolded description text about what clicking will do

                  var tooltipString;
                  switch (member.categoryCraftingClass) {
                     case 'enabledCrafting':
                        tooltipString = `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.status_all_enabled')}</div><div class='verticalSpacer'>` +
                              i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.disable_all_description', data) + '</div>';
                        break;
                     case 'allDisabledCrafting':
                        tooltipString = `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.status_all_disabled')}</div><div class='verticalSpacer'>` +
                              i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.enable_all_description', data) + '</div>';
                        break;
                     case 'someEnabledCrafting':
                        tooltipString = `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.status_some_enabled')}</div><div class='verticalSpacer'>` +
                        i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.enable_all_description', data) + '</div>';
                        break;
                  }

                  tooltipString += '<div class="details"><div class="stat"><span>' +
                        i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.proficiencies') + '</span></div>';

                  categories.forEach(function(category) {
                     var categoryName = i18n.t(category.category);
                     var proficiency = Math.min(100, Math.floor(category.proficiency * 100));
                     var headerClass = category.enabled ? 'available' : 'unavailable';
                     tooltipString += `<div class="stat"><span class="header ${headerClass}">${categoryName}</span><span class="value">${proficiency}</span>%</div>`;
                  });
                  tooltipString += '</div>';

                  return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.title', data), tooltipString));
               }
            });
         });
      });
   },

   // Go through recipes displayed and update based on whether recipe is now craftable or not
   _updateCraftableRecipes: function() {
      var self = this;
      var recipeItems = self.$('.item');
      if (recipeItems) {
         var highestLevel = self.get('model.highest_level');
         $.each(recipeItems, function(_, el) {
            var item = $(el);
            var recipeKey = item.attr('recipe_key');
            var recipe = self.allRecipes[recipeKey];
            if (recipe) {
               Ember.set(recipe, 'is_craftable', self._areRequirementsMet(recipe, highestLevel) ? 1 : 0);
               item.attr('is_craftable', recipe.is_craftable);
            }
         });
      }
   }.observes('model.highest_level'),

   // Adding ingredient and workshop details to the recipe is expensive
   // so do it on demand we when we access a recipe.
   // ACE: override this function to add stacks consideration to ingredients
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

   //Something with an ordinal of 1 should have precedence
   _compareByOrdinal: function(a, b) {
      return (a.ordinal - b.ordinal);
   },

   // ACE: Sort the recipies first by their level requirement, *then by ordinal*, and finally by their user visible name
   _compareByLevelAndAlphabetical: function(a, b) {
      // put all auto-craft recipes at the end
      if (a.is_auto_craft && !b.is_auto_craft) {
         return 1;
      }
      else if (!a.is_auto_craft && b.is_auto_craft) {
         return -1;
      }

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

   //Updates the recipe display (note: now that this is just a variable, do we need a separate observer?)
   _updateRecipeLocking: function() {
      Ember.run.scheduleOnce('afterRender', this, '_setPreviewStyling');
   }.observes('model.highest_level', 'model.manually_unlocked'),

   _onCurrentRecipeChanged: function() {
      Ember.run.scheduleOnce('afterRender', this, '_setPreviewStyling');
   }.observes('currentRecipe'),

   _addExtraCraftOrderConditions: function(recipe, condition) {
      var self = this;
      if (stonehearth_ace.isShiftKeyActive()) {
         condition.order_index = 1;
      }
   },

   selectRecipe: function(recipe_key, remaining, maintainNumber) {
      var self = this;
      self.set('currentRecipe', self._getOrCalculateRecipeData(recipe_key));
      self.queueAnywayStatus = false;
      if (self.currentRecipe) {
         //You'd think that when the object updated, the variable would update, but noooooo
         self.set('model.current', self.currentRecipe);
         self._setRadioButtons(remaining, maintainNumber);
         //TODO: make the selected item visually distinct
         self.preview();
      }
   },

   actions: {
      hide: function () {
         this.hide(true);
      },

      select: function(object, remaining, maintainNumber) {
         if (object) {
            self.selectRecipe(object.recipe_key, remaining, maintainNumber);
         }
      },

      //Call this function when the user is ready to submit an order
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
         if (type == "maintain" || recipe.is_auto_craft) {
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
      },

      //delete the current order
      delete: function(orderId) {
         var orderList = this.getOrderList();
         radiant.call_obj(orderList, 'delete_order_command', orderId)
            .done(function(returnData){
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash'} );
            });
      },

      queueAnyway: function() {
         this._showCraftUI(true);
         this.queueAnywayStatus = true;
      },

      //Does anyone use this functionality?
      togglePause: function(){
         var orderList = this.getOrderList()

         if (this.get('model.order_list.is_paused')) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:open'} );
         } else {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:closed'} );
         }
         radiant.call_obj(orderList, 'toggle_pause');
      },

      toggleSecondaryListPause: function(){
         if (this.get('model.order_list.is_secondary_list_paused')) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:open'} );
         } else {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:closed'} );
         }
         radiant.call('stonehearth_ace:toggle_secondary_order_list_pause', this.get('model.alias'));
      },

      scrollOrderListUp: function() {
         this._scrollOrderList(this.$('#orderList'), -this.scrollAmount);
      },

      scrollOrderListDown: function() {
         this._scrollOrderList(this.$('#orderList'), this.scrollAmount);
      },

      scrollsecondaryOrderListUp: function() {
         this._scrollOrderList(this.$('#secondaryOrderList'), -this.scrollAmount);
      },

      scrollsecondaryOrderListDown: function() {
         this._scrollOrderList(this.$('#secondaryOrderList'), this.scrollAmount);
      },
   },

   isListForOrderPaused: function(order) {
      // if the order is in the primary list, return whether that list is enabled
      // otherwise return whether the secondary list is enabled
      var self = this;
      var orders = self.get('model.order_list.orders') || [];
      for (var i = 0; i < orders.length; i++) {
         if (orders[i].id == order.id) {
            return self.get('model.workshopIsPaused');
         }
      }

      return self.get('model.secondaryListIsPaused');
   },

   // Fires whenever the workshop changes, but the first update is all we really
   // care about. Recipes is saved on the context and updated when the recipe list first comes in
   // TODO: can't that fn just call _build_workshop_ui?
   _contentChanged: function() {
      Ember.run.scheduleOnce('afterRender', this, '_build_workshop_ui');
      Ember.run.scheduleOnce('afterRender', this, '_applySearchFilter');
   }.observes('recipes'),

   _ordersTableSortable: function(table) {
      var self = this;
      var sortableOrders = self.makeSortable(self.$(table), {
         axis: "y",
         start: function(event, ui) {
            // on drag start, creates a temporary attribute on the element with the old index
            $(this).attr('data-previndex', ui.item.index()+1);
            self.is_sorting = ui.item[0];
         },
         stop: function(event, ui) {
            //if we're not sorting anymore, don't do anything
            if (self.is_sorting == null) {
               return;
            }
            //If we're still sorting, then update the order list
            var newPos = ui.item.index() + 1;
            //aha, all is explained. Wrong variable name ::sigh::
            var id =  parseInt(ui.item.attr("data"));

            //Check if we're replacing?
            if ($(this).attr('data-previndex') == newPos) {
               return;
            }

            radiant.call_obj(self.getOrderList(), 'change_order_position_command', newPos, id);

            //Let people know we're no longer sorting
            self.is_sorting = null;
         }
      });

      if (sortableOrders) {
         sortableOrders.disableSelection();
      }

      return sortableOrders;
   },

   //Called once when the model is loaded
   // ACE: override to modify search to allow searching ingredients and descriptions
   _build_workshop_ui: function() {
      var self = this;

      if (!self.$("#craftWindow")) {
         return;
      }

      self._buildOrderList(self.$('#orderList'), self.get('model.order_list.orders'));
      var secondaryOrders = self.get('model.order_list.secondary_orders');
      var autoCraftOrders = self.get('model.order_list.auto_craft_orders');
      self._buildOrderList(self.$('#secondaryOrderList'),
            (secondaryOrders && secondaryOrders.length > 0) || (autoCraftOrders && autoCraftOrders.length > 0));

      //build the order list(s) on the order tab
      self._ordersTableSortable('#makeOrdersTable');
      self._ordersTableSortable('#secondaryOrdersTable');
      self._ordersTableSortable('#autoCraftOrdersTable');

      $(document).on('keyup.show_team_workshop keydown.show_team_workshop', function(e){
         self._updateCraftInsertShown();
      });

      self.$("#craftButton").hover(function() {
            $(this).find('#craftButtonLabel').fadeIn();
            self.HOVERING_CRAFT_BUTTON = true;
            self.set('insertRecipePortrait', self.get('currentRecipe.portrait'));
            self._updateCraftInsertShown();
         }, function () {
            $(this).find('#craftButtonLabel').fadeOut();
            self.HOVERING_CRAFT_BUTTON = false;
            self._updateCraftInsertShown();
         });

      self.$(".category").on({
         mouseenter: function() {
            var recipe = self._getOrCalculateRecipeData($(this).attr('recipe_key'));
            if (recipe) {
               self.HOVERING_ITEM = true;
               self._hoveredRecipeIsAutoCraft = recipe.is_auto_craft;
               self.set('insertRecipePortrait', recipe.portrait);
               self._updateCraftInsertShown();
            }
         },
         mouseleave: function () {
            self.HOVERING_ITEM = false;
            self._updateCraftInsertShown();
         }}, '.item');

      var tooltip = App.tooltipHelper.createTooltip(
         i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.title'),
         i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.description'));
      self.$('#craftButton').tooltipster({
         delay: 1000,
         content: $(tooltip)
      }); 

      // Perform filter after keyup to ensure that key has already been applied
      self.searchInput = self.$('#searchInput');
      self.searchInput.keydown(function (e) {
         if (e.key == 'Escape') {
            e.stopPropagation();
         }
      });
      self.searchInput.keyup(function (e) {
         if (e.key == 'Escape') {
            self.searchInput.val('');
            e.stopPropagation();
         }

         var search = $(this).val().toLowerCase();
         self._curSearchTerm = search;

         self._applySearchFilter();

         if (e.key == 'Enter' || e.key == 'Escape') {
            self.searchInput.blur();
            self.$('#searchContainer').blur();
         }
      });
      
      // when it has focus, show the extra settings
      self._focusCheckIntervalID = null;
      self.$('#searchContainer').focusin(function (e) {
         self.set('showSearchSettings', true);
         if (self._focusCheckIntervalID != null) {
            clearInterval(self._focusCheckIntervalID);
            self._focusCheckIntervalID = null;
         }
      });
      self.$('#searchContainer').focusout(function (e) {
         if (self._focusCheckIntervalID != null) {
            clearInterval(self._focusCheckIntervalID);
            self._focusCheckIntervalID = null;
         }
         self._focusCheckIntervalID = setInterval(function() {
            if (!stonehearth_ace.isMouseDown()) {
               clearInterval(self._focusCheckIntervalID);
               self._focusCheckIntervalID = null;
               self.set('showSearchSettings', false);
            }
         }, 100);
      });

      App.guiHelper.addTooltip(self.$('#searchTitleDiv'), 'stonehearth_ace:ui.game.show_workshop.search_title_description');
      App.guiHelper.addTooltip(self.$('#searchDescriptionDiv'), 'stonehearth_ace:ui.game.show_workshop.search_description_description');
      App.guiHelper.addTooltip(self.$('#searchIngredientsDiv'), 'stonehearth_ace:ui.game.show_workshop.search_ingredients_description');

      //App.tooltipHelper.createDynamicTooltip(self.$('[title]'));
      App.guiHelper.createDynamicTooltip(self.$('#recipeItems'), '.interactionOverlay', function($el) {
         var key = $el.parent().attr('recipe_key');
         var recipe = self._getOrCalculateRecipeData(key);
         var jobAlias = self.get('model.alias');
         var options = {
            recipe_key: jobAlias + "|" + key,
            display_name: recipe.display_name,
            description: recipe.description,
         };
         if (recipe.product_stacks) {
            options.self = {'stonehearth:stacks': {stacks: recipe.product_stacks}};
         }
         var tooltip = $(App.guiHelper.createUriTooltip(recipe.product_uri, options));

         // if the recipe has already-queued orders, show them in the tooltip
         var queuedOrders = self._orderRecipeMap[key];
         if (queuedOrders) {
            // show the total number of orders; also show the total make amount and the max maintain amount
            var totalOrders = queuedOrders.length;
            var totalMakeAmount = 0;
            var maxMaintainAmount = 0;
            for (var i = 0; i < totalOrders; i++) {
               var order = queuedOrders[i];
               if (order.condition.type == 'maintain') {
                  maxMaintainAmount = Math.max(maxMaintainAmount, order.condition.at_least);
               }
               else {
                  totalMakeAmount += order.condition.remaining;
               }
            }

            var queuedOrdersString = i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_queued_orders', {count: totalOrders});
            var div = `<div class='stat verticalSpacer'>${queuedOrdersString}`;
            if (totalMakeAmount > 0) {
               div += `<div class='indented'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_total_make_amount', {amount: totalMakeAmount})}</div>`;
            }
            if (maxMaintainAmount > 0) {
               div += `<div class='indented'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_max_maintain_amount', {amount: maxMaintainAmount})}</div>`;
            }

            tooltip.append($(div + '</div>'));
         }

         return tooltip;
      });

      App.guiHelper.createDynamicTooltip(self.$('#craftingWindow'), '.statusSign', function($el) {
         var id = $el.attr('id');
         var title, text;
         if (id == 'secondaryListStatusSign') {
            title = 'stonehearth_ace:ui.game.show_workshop.status_sign.secondary_list_title';
            text = 'stonehearth_ace:ui.game.show_workshop.status_sign.secondary_list_description';
         }
         else {
            title = 'stonehearth_ace:ui.game.show_workshop.status_sign.title';
            text = 'stonehearth_ace:ui.game.show_workshop.status_sign.description';
         }
         return $(App.tooltipHelper.createTooltip(i18n.t(title), i18n.t(text)));
      });

      // Select the first recipe if currentRecipe isn't set.
      // Current recipe can be set by autotest before we reach this point.
      if (!this.currentRecipe) {
         this._selectFirstValidRecipe();
      }
   },

   _showCraftOrderTooltip: function($el, order, showToRight) {
      var self = this;

      // if it's not a building order, offer the ability to modify the quantity
      // if it's a maintain/auto-craft order, show tooltip on the left side; otherwise, show it on the right side
      var recipe = order.recipe;
      var title = i18n.t(recipe.recipe_name);
      var description;

      if (recipe.is_auto_craft) {
         description = `<div class='stat craftOrderAuto'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_auto_craft_order')}</div>`;
      }
      else if (order.condition.type == 'maintain') {
         description = `<div class='stat craftOrderMaintain'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_manual_maintain_order')}</div>`;
      }
      else {
         description = `<div class='stat craftOrderMake'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_manual_make_order')}</div>`;
      }

      if (order.condition.type == 'maintain') {
         description +=
            `<div class='verticalSpacer stat'><span class='header'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_maintain')}</span><span class='value'>${order.condition.at_least}</span></div>`;
      }
      else {
         var quantity = i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_make_quantity', order.condition);
         description +=
            `<div class='verticalSpacer stat'><span class='header'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_make')}</span>${quantity}</div>`;
      }

      if (order.building_id) {
         var gmm = App.getGameModeManager();
         var buildView = gmm.getView(gmm.modes.BUILD)._buildingDesignerView;
         if (buildView) {
            var building = buildView.getBuildingById(order.building_id);
            var name = building && building['stonehearth:unit_info'] && (building['stonehearth:unit_info'].custom_name || building['stonehearth:unit_info'].display_name);
            if (name) {
               name = i18n.t(name);
               description += `<div class='verticalSpacer stat'><span class='header'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_building')}</span>"<span class='value'>${name}</span>"</div>`;
            }
         }
      }

      // for a building order or an order with associated orders, list those appropriately
      if (self.childOrders != null && self.childOrders.length > 0) {
         var sOrders = '';
         var totalCount = 0;
         for (var i = 0; i < self.childOrders.length; i++) {
            var o = self.childOrders[i].order;
            var count = o.condition.at_least || o.condition.remaining;
            var isActive = o.curr_crafters.length > 0;
            var valueClass = 'value';

            var workshop = App.workshopManager.getWorkshopByOrderList(o.order_list);
            if (workshop && workshop.isListForOrderPaused(o)) {
               valueClass = 'craftOrderPaused';
            }
            else if (isActive) {
               valueClass = 'available';
            }
            else if (workshop) {
               var recipe = workshop._getOrCalculateRecipeData(o.recipe.recipe_key);
               var failedRequirements = recipe && workshop._calculate_failed_requirements(recipe);
               if (failedRequirements && failedRequirements != '') {
                  valueClass = 'unavailable';
               }
            }

            var sCount = i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_associated_order_count', {count: count, valueClass: valueClass});
            sOrders += `<div class='stat'><img class='imgHeader' src='${o.recipe.portrait}'/>${sCount}</div>`;
            totalCount += 1;
         }

         // if the order has associated orders, list direct children, direct parent, and all other associated orders
         // for now just list the direct children that will be removed if this order is removed
         if (totalCount > 0) {
            description += `<div class='verticalSpacer stat'><span class='header'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_associated_orders')}</span></div>`;
                  //+ `${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_associated_order_count', {count: totalCount})}</div>`;
            description += `<div class='flexContainer faded'>${sOrders}</div>`;
         }
      }

      // add currently crafting crafter(s)
      var crafters = [];
      if (order.curr_crafters.length > 0) {
         for (i = 0; i < order.curr_crafters.length; i++) {
            var crafter = order.curr_crafters[i];
            var member = self._memberLookup[radiant.getEntityId(crafter)];
            if (member) {
               var id = crafter.__self;

               var crafterName = i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_current_crafter', member);
               var sCrafter = `<img class='imgHeader' src='/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=${id}'/>${crafterName}`;
               crafters.push(sCrafter);
            }
         }

         if (crafters.length == 1) {
            // if there's just one crafter, put it on the same line as the header
            description += `<div class='verticalSpacer stat'><span class='header available'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_crafting')}</span>${crafters[0]}</div>`;
         }
         else if (crafters.length > 1) {
            var sCrafters = crafters.join('</div><div class="stat indented">');
            description += `<div class='verticalSpacer stat'><span class='header available'>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_crafting')}</span></div><div class="stat indented">${sCrafters}</div>`;
         }
      }

      // add issues / failed requirements
      if (crafters.length == 0 && order.order_progress != 3) {
         var recipe = self._getOrCalculateRecipeData(order.recipe.recipe_key);
         failedRequirements = recipe && self._calculate_failed_requirements(recipe);
         if (failedRequirements) {
            description += `<div class='verticalSpacer stat unavailable'>${failedRequirements}</div>`;
         }
      }

      // show interaction tips
      var tips = `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_modify_order')}</div>`;
      tips += `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_move_order')}</div>`;
      tips += `<div>${i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_remove_order')}</div>`;

      description += `<div class="verticalSpacer stat faded">${tips}</div>`

      var tooltip = $(App.tooltipHelper.createTooltip(title, description));
      var $iEl = $el.find('.interactionOverlay');
      if ($iEl.data('tooltipster')) {
         $iEl.tooltipster('destroy');
      }
      $iEl.tooltipster({
         content: tooltip,
         position: showToRight ? 'right' : 'left',
      });
      $iEl.tooltipster('show');
   },

   _applySearchFilter: function() {
      var self = this;
      var search = self._curSearchTerm;

      var searchTitle = self.get('searchTitle');
      var searchDescription = self.get('searchDescription');
      var searchIngredients = self.get('searchIngredients');
      // if not searching for anything, just cancel
      if (!searchTitle && !searchDescription && !searchIngredients) {
         return;
      }

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
         });

         self.$('.category').each(function(i, category) {
            var el = $(category)

            if (el.find('.item:visible').length > 0) {
               el.show();
            } else {
               el.hide();
            }
         });
      }
   },

   _shouldShowSecondaryOrders: function() {
      var secondaryOrders = this.get('model.order_list.secondary_orders') || [];
      var autoCraftOrders = this.get('model.order_list.auto_craft_orders') || [];
      this.set('showSecondaryOrderList', secondaryOrders.length > 0 || autoCraftOrders.length > 0 ||
            this.get('isShowingSecondaryCraftInsert') || this.get('isShowingAutoCraftInsert'));
   }.observes('model.order_list.secondary_orders', 'model.order_list.auto_craft_orders', 'isShowingSecondaryCraftInsert', 'isShowingAutoCraftInsert'),

   _autoCraftOrdersChanged: function() {
      $(this).trigger('stonehearth_ace:workshop:auto_craft_orders_changed');
   }.observes('model.order_list.auto_craft_orders'),

   hasAutoCraftOrder: function(recipe_key) {
      var autoCraftOrders = this.get('model.order_list.auto_craft_orders') || [];
      for (var i = 0; i < autoCraftOrders.length; i++) {
         if (autoCraftOrders[i].recipe.recipe_key == recipe_key) {
            return true;
         }
      }

      return false;
   },

   _isCurrentOrderTypeAutoCraft: function() {
      return this._getOrCalculateRecipeData(this.currentRecipe.recipe_key).is_auto_craft;
   },

   _isCurrentOrderTypeMaintain: function() {
      var type = this.$('input[name=' + this.get('orderTypeName') + ']:checked').val();
      return type == "maintain" && !this._getOrCalculateRecipeData(this.currentRecipe.recipe_key).is_auto_craft;
   },

   _updateCraftInsertShown: function() {
      var self = this;
      var show = stonehearth_ace.isShiftKeyActive() && (self.HOVERING_CRAFT_BUTTON || self.HOVERING_ITEM);

      var makeDiv = self.$('.insertPrimary');
      var maintainDiv = self.$('.insertSecondary');
      var autoCraftDiv = self.$('.insertAutoCraft');

      makeDiv.hide();
      maintainDiv.hide();
      autoCraftDiv.hide();

      var isShowingAutoCraftInsert = false;
      var isShowingSecondaryCraftInsert = false;
      if (show) {
         if ((self.HOVERING_CRAFT_BUTTON && self._isCurrentOrderTypeAutoCraft()) ||
               (self.HOVERING_ITEM && self._hoveredRecipeIsAutoCraft)) {
            autoCraftDiv.show();
            isShowingAutoCraftInsert = true;
         }
         else if ((self.HOVERING_CRAFT_BUTTON && self._isCurrentOrderTypeMaintain()) ||
               (self.HOVERING_ITEM && stonehearth_ace.isCtrlKeyActive())) {
            maintainDiv.show();
            isShowingSecondaryCraftInsert = true;
         }
         else {
            makeDiv.show();
         }
      }

      self.set('isShowingAutoCraftInsert', isShowingAutoCraftInsert);
      self.set('isShowingSecondaryCraftInsert', isShowingSecondaryCraftInsert);
   },

   _focusAndKeyUpSearchInput: function() {
      var self = this;
      // we only care about this if the search setting checkboxes are visible; otherwise they're just initializing
      if (self.get('showSearchSettings')) {
         self.$('#searchInput').focus();
         self.$('#searchInput').keyup();
      }
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
      return str && str.toLowerCase().indexOf(search) != -1;
   },

   _selectFirstValidRecipe: function() {
      for (var i = 0; i < this.recipes.length; i++) {
         var recipes = this.recipes[i].recipes;
         for (var j = 0; j < recipes.length; j++) {
            if (!recipes[j].is_locked) {
               this.set('currentRecipe', this._getOrCalculateRecipeData(recipes[j].recipe_key));
               this.preview();
               return;
            }
         }
      }
   },

   _setRadioButtons: function (remaining, maintainNumber) {
      var self = this;
      //Set the radio buttons correctly
      if (remaining) {
         self.$("#makeNumSelector").val(remaining);
         self.$('#' + self.get('orderTypeMakeId')).prop("checked", "checked");
      } else {
         self.$("#makeNumSelector").val("1");
         self.$('#' + self.get('orderTypeMakeId')).prop("checked", false);
      }
      if (maintainNumber) {
         self.$("#maintainNumSelector").val(maintainNumber);
         self.$('#' + self.get('orderTypeMaintainId')).prop("checked", "checked");
      } else {
         self.$("#maintainNumSelector").val("1");
         self.$('#' + self.get('orderTypeMaintainId')).prop("checked", false);
      }
      if (!remaining && !maintainNumber) {
         self.$('#' + self.get('orderTypeMakeId')).prop("checked", "checked");
      }
   },

   _constructMaterialsToQuery: function () {
      var self = this;
      self._materialsToQuery = {};
      radiant.each(self.get('model.recipe_list'), function (_, category) {
         radiant.each(category.recipes, function (_, recipe_info) {
            radiant.each(recipe_info.recipe.ingredients, function (_, ingredient) {
               if (ingredient.material) {
                  self._materialsToQuery[ingredient.material] = true;
               }
            });
         });
      });
   }.observes('model.recipe_list'),

   _updateCategoryCraftersTooltips: function() {
      // when the recipes get updated, wait for Ember.run.scheduleOnce('afterRender',) and then do dynamic tooltips
      var self = this;
      Ember.run.scheduleOnce('afterRender', function() {
         self.$('#recipeItems .categoryCrafter').each(function() {
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
                     category: self.allCategories[category].category,
                  };

                  var tooltipString = disable && i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.disable_description', data) ||
                        i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.enable_description', data);

                  tooltipString += '<div class="details"><div class="stat"><span class="header">' +
                        i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.proficiency') +
                        `</span><span class="value">${Math.min(100, Math.floor((member.category_profiencies[category] || 0) * 100))}</span>%</div></div>`;

                  return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.show_workshop.category_crafter.title', data), tooltipString));
               }
            });
         });
      });
   }.observes('recipes'),

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

   _updateAlreadyQueuedRecipes: function() {
      var self = this;

      var orders = (self.get('model.order_list.orders') || []).concat(
         (self.get('model.order_list.secondary_orders') || []).concat(self.get('model.order_list.auto_craft_orders') || []));
      var orderRecipeMap = {};
      for (var i = 0; i < orders.length; i++) {
         var recipeKey = orders[i].recipe.recipe_key;
         var recipeOrders = orderRecipeMap[recipeKey];
         if (!recipeOrders) {
            recipeOrders = [];
            orderRecipeMap[recipeKey] = recipeOrders;
         }
         recipeOrders.push(orders[i]);
      }
      self._orderRecipeMap = orderRecipeMap;

      var recipes = self.get('recipes');
      radiant.each(recipes, function(_, recipeCategory) {
         radiant.each(recipeCategory.recipes, function(_, recipe) {
            var isAlreadyQueued = orderRecipeMap[recipe.recipe_key] != null;
            if (recipe.is_already_queued != isAlreadyQueued) {
               Ember.set(recipe, 'is_already_queued', isAlreadyQueued);
            }
         });
      });
   }.observes('recipes', 'model.order_list.orders', 'model.order_list.secondary_orders', 'model.order_list.auto_craft_orders'),

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
   
   // ACE: handle gold stacks
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
   
   _findUsableCount: function (ingredientData) {
      return (ingredientData.kind == 'uri' ? this._usableUris : this._usableMaterials)[ingredientData.identifier] || 0;
   },

   //When the order list updates, or when the inventory tracker updates, re-evaluate the requirements
   //on the details page
   _updateFullDetailedOrderList: function() {
      this._updateOrdersInDetailedOrderList();
      this._updateSecondaryOrdersInDetailedOrderList();
   },

   _updateOrdersInDetailedOrderList: function() {
      this._updateDetailedOrderList(this.$('#orderList'), this.get('model.order_list.orders'));
   },

   _updateSecondaryOrdersInDetailedOrderList: function() {
      this._updateDetailedOrderList(this.$('#secondaryOrderList'),
            (this.get('model.order_list.secondary_orders') || []).concat(this.get('model.order_list.auto_craft_orders') || []));
   },

   _updateDetailedOrderList: function(orderList, orders) {
      var self = this;
      if (!orders || !self.$('.orderListItem') || !self._recipeListInitialized) {
         return;
      }
      for (var i = 0; i < orders.length; i++) {
         var order = orders[i];
         if (!order || !order.recipe || !order.recipe.recipe_key) {
            //can happen if the recipe is being destroyed as the update happens
            return;
         }
         var recipe = self._getOrCalculateRecipeData(order.recipe.recipe_key);
         if (!recipe) {
            //can happen if the recipe is being destroyed as the update happens
            return;
         }

         //var recipe = order.recipe;
         var orderListRow = self.$('.orderListRow[data ="' + orders[i].id + '"]');
         var orderListItem = self.$('.orderListItem[data-orderid = "' + order.id + '"]');
         var $issueIcon = orderListItem.find('.issueIcon');
         //var $interactionOverlay = orderListItem.find('.interactionOverlay');

         var failedRequirements = "";
         // Only calculate failed requirements if this recipe isn't currently being processed (stonehearth.constants.crafting_status.CRAFTING = 3)
         if (order.order_progress != 3 && order.curr_crafters.length == 0) {
            failedRequirements = self._calculate_failed_requirements(recipe);
         }
         var currentText = orderListRow.find('.orderListRowCraftingStatus').text();
         if (failedRequirements != currentText) {
            orderListRow.find('.orderListRowCraftingStatus').html(failedRequirements);
         }
         if (failedRequirements != "") {
            //display a badge on the RHS order list also
            $issueIcon.show();
         } else {
            //remove any badge on the RHS order list
            $issueIcon.hide();
         }

         //if we have a curr crafter, show their portrait
         var curCrafters = order.curr_crafters;
         if (curCrafters.length > 0) {
            // if the recipe for this order indicates it's an auto-craft recipe,
            // then it can only be performed by an auto-crafter, so just show the entity icon
            for (j = 0; j < curCrafters.length; j++) {
               var crafter = curCrafters[j];
               var crafterDiv = orderListRow.find(`.workerPortrait[crafter_id='${crafter.__self}']`);
               if (crafterDiv.length > 0) {
                  if (recipe.is_auto_craft) {
                     var catalogData = crafter && App.catalog.getCatalogData(crafter.uri);
                     crafterDiv.attr('src', catalogData && catalogData.icon);
                  }
                  else {
                     crafterDiv.attr('src', '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + crafter.__self);
                  }
               }
            }
         }

         // if this order should be highlighted, highlight it
         var highlighted = false;
         if (self.highlightType && !self._isModifyingOrder) {
            for (var j = 0; j < self.highlightedOrders.length; j++) {
               var o = self.highlightedOrders[j];
               if (!o.isLocal) {
                  break;
               }
               if (o.order.id == order.id) {
                  orderListItem.addClass(self.highlightType);
                  highlighted = true;
                  break;
               }
            }
         }

         if (!highlighted) {
            orderListItem.removeClass('buildingHighlighted craftHighlighted');
         }
      }

      self._updateButtonStates(orderList);
   },

   //returns a string of unmet requirements
   _calculate_failed_requirements: function(localRecipe) {
      var self = this;
      var requirementsString = "";
      var recipe = self._getOrCalculateRecipeData(localRecipe.recipe_key);
      if (!recipe) {
         recipe = localRecipe;
      }
      var jobAlias = self.get('model.alias');

      //If there is no placed workshop, note this, in red
      var workshopData = null;
      var autoCrafters = [];
      if (App.workshopManager.workbenchItemTrackerData && recipe.hasWorkshop) {
         workshopData = App.workshopManager.workbenchItemTrackerData[recipe.workshop.uri]
         if (!workshopData && recipe.workshop.equivalents) {
            for (var i = 0; i < recipe.workshop.equivalents.length; ++i) {
               workshopData = App.workshopManager.workbenchItemTrackerData[recipe.workshop.equivalents[i]];
               if (workshopData) {
                  if (recipe.is_auto_craft) {
                     // if it's an auto-craft recipe, go through and find if any auto-crafters have it enabled
                     radiant.each(workshopData.items, function(_, item) {
                        autoCrafters.push(item);
                     });
                  }
                  else {
                     break;
                  }
               }
            }
         }

         if (!workshopData || (recipe.is_auto_craft && autoCrafters.length == 0)) {
            requirementsString = i18n.t('stonehearth:ui.game.show_workshop.workshop_required') + recipe.workshop.name + '<br>'
         }
      }

      //If there is no crafter of appropriate level, mention it
      // for auto-crafters, make sure the recipe is enabled and they have a non-zero workshop crafting modifier
      if (recipe.is_auto_craft) {
         if (autoCrafters.length > 0) {
            var canCraft = false;
            for (var i = 0; i < autoCrafters.length; i++) {
               var workshopComp = autoCrafters[i]['stonehearth:workshop'];
               if (workshopComp && workshopComp.crafting_time_modifier > 0) {
                  var autoCraftComp = autoCrafters[i]['stonehearth_ace:crafting_auto_crafter'];
                  if (autoCraftComp) {
                     for (var j = 0; j < autoCraftComp.enabled_recipes.length; j++) {
                        if (autoCraftComp.enabled_recipes[j].recipe_key == recipe.recipe_key &&
                              autoCraftComp.enabled_recipes[j].job == jobAlias) {
                           canCraft = true;
                           break;
                        }
                     }
                  }
               }

               if (canCraft) {
                  break;
               }
            }

            if (!canCraft) {
               requirementsString = requirementsString + i18n.t('stonehearth_ace:ui.game.show_workshop.auto_crafter_enabled_needed') + '<br>';
            }
         }
      }
      else {
         var curr_level = this.get('model.highest_level')
         if (recipe.level_requirement > curr_level) {
            requirementsString = requirementsString +
                                 i18n.t('stonehearth:ui.game.show_workshop.level_requirement_needed') +
                                 i18n.t(self.get('model.class_name')) +
                                 i18n.t('stonehearth:ui.game.show_workshop.level_requirement_level') +
                                 recipe.level_requirement + '<br>';
         }
         else {
            // check if the are no crafters of the appropriate level *who have the category enabled*
            var members = self._memberArray || [];
            var canCraft = false;
            for (var i = 0; i < members.length; i++) {
               if (members[i].level >= recipe.level_requirement && !members[i].disabledCategories[recipe.category]) {
                  canCraft = true;
                  break;
               }
            }

            if (!canCraft) {
               var category = self.allCategories[recipe.category];
               requirementsString = requirementsString +
                                 i18n.t('stonehearth_ace:ui.game.show_workshop.category_level_requirement_needed', {
                                    category: category.category,
                                    class: self.get('model.class_name'),
                                    level: recipe.level_requirement || 1,
                                 }) + '<br>';
            }
         }
      }

      //if they have missing ingredients, list those here
      var missingIngredients = [];
      if (App.workshopManager.usableItemTrackerData) {
         for (i = 0; i < recipe.ingredients.length; i++) {
            var ingredientData = recipe.ingredients[i];
            var numNeeded = ingredientData.count;
            var numHave = self._findUsableCount(ingredientData);
            if (numHave < numNeeded) {
               missingIngredients.push(numHave + '/' + numNeeded + " " + i18n.t(ingredientData.name));
            }
         }
      }
      if (missingIngredients.length > 0) {
         var ingredientString = i18n.t('stonehearth:ui.game.show_workshop.missing_ingredients') + missingIngredients.join(', ');
         requirementsString = requirementsString + ingredientString;
      }

      return requirementsString
   },

   // ACE: have to override this whole function just to get rid of the >999 truncating for stacks
   _setPreviewStyling: function() {
      var self = this;
      if (!self.$()) {
         return;  // Menu already closed.
      }
      App.guiHelper.createDynamicTooltip(self.$(), '[title]', ($el) => i18n.t($el.attr('title')));

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

   _areRequirementsMet: function (recipe, highestLevel) {
      var self = this;

      // High enough level?
      if (recipe.level_requirement > highestLevel) {
         return false;
      }

      // Note: the basic and usable inventory trackers may be null if the traces haven't fired yet
      // but the recipes array will be rebuilt 
      // Have workshop?
      if (self.workshopData && recipe.hasWorkshop) {
         var workshopData = self.workshopData[recipe.workshop.uri];
         if (!workshopData && recipe.workshop.equivalents) {
            for (var i = 0; i < recipe.workshop.equivalents.length; ++i) {
               workshopData = self.workshopData[recipe.workshop.equivalents[i]];
               if (workshopData) {
                  break;
               }
            }
         }
         if (workshopData) {
            return false;
         }
      }

      // Have ingredients?
      if (App.workshopManager.usableItemTrackerData) {
         for (var i = 0; i < recipe.ingredients.length; ++i) {
            var ingredient = recipe.ingredients[i];

            // Format ingredient identifiers for findUsableCount
            // if it hasn't already been initialized
            if (!ingredient.identifier) {
               if (ingredient.material) {
                  ingredient.identifier = ingredient.material;
                  ingredient.kind = 'material';
               } else {
                  ingredient.identifier = ingredient.uri;
                  ingredient.kind = 'uri';
               }
            }

            var numHave = self._findUsableCount(ingredient);
            if (numHave < ingredient.count) {
               return false;
            }
         }
      } else {
         return false;
      }

      return true;
   },

   _showCraftUI: function (shouldShow) {
      var self = this;
      if (shouldShow || this.queueAnywayStatus) {
         self.$('#craftWindow #orderOptionsLocked').hide();
         self.$("#craftWindow #orderOptions").show();
      } else {
         self.$("#craftWindow #orderOptions").hide();
         self.$('#craftWindow #orderOptionsLocked').show();
      }
   },

   // ACE: have to override this just for the stacks
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

   _getPropertyValue: function (product, catalogData, key) {
      var propertyValue = catalogData[key];
      var displayValue = propertyValue;
      if (key == 'net_worth' && product && product.stacks) {
         displayValue = propertyValue * product.stacks;
      }
      return displayValue;
   },
   
   // ACE: use helper functions for stats and stat tooltips
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
      if (catalogData['combat_range']) {
         statHtml += '<div class="stat range">' + catalogData['combat_range'] + '<br><span class=name>' + i18n.t('stonehearth_ace:ui.game.show_workshop.range_stat') + '</span></div>';
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
      if (catalogData['fuel_amount']) {
         statHtml += self._formattedRecipeProductProperty(recipe, 'fuel_amount', 'fuelAmount');
      }
      if (catalogData['food_satisfaction']) {
         var level = stonehearth_ace.getSatisfactionLevel(App.constants.food_satisfaction_thresholds, catalogData['food_satisfaction']);
         statHtml += self._formattedRecipeProductProperty(recipe, 'food_servings', 'satisfaction food ' + level);
         //statHtml += `<div class="stat satisfaction">${catalogData['food_servings']} x <img class="food_${level}"/></div>`;
      }
      if (catalogData['drink_satisfaction']) {
         var level = stonehearth_ace.getSatisfactionLevel(App.constants.drink_satisfaction_thresholds, catalogData['drink_satisfaction']);
         statHtml += self._formattedRecipeProductProperty(recipe, 'drink_servings', 'satisfaction drink ' + level);
         //statHtml += `<div class="stat satisfaction">${catalogData['drink_servings']} x <img class="drink_${level}"/></div>`;
      }
      if (catalogData['is_animal_feed']) {
         statHtml += self._formattedRecipeProductProperty(recipe, 'food_servings', 'satisfaction food animal');
         //statHtml += `<div class="stat satisfaction">${catalogData['food_servings']} x <img class="food_${level}"/></div>`;
      }

      return statHtml;
   },

   _addStatTooltips: function(catalogData) {
      var self = this;

      App.tooltipHelper.createDynamicTooltip(self.$('.stat.appeal'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_appeal_stat'); });
      App.tooltipHelper.createDynamicTooltip(self.$('.stat.netWorth'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_net_worth_stat'); });
      App.tooltipHelper.createDynamicTooltip(self.$('.stat.effort'), function () { return i18n.t('stonehearth:ui.game.show_workshop.tooltip_effort_stat'); });
      App.tooltipHelper.createDynamicTooltip(self.$('.stat.fuelAmount'), function () { return i18n.t('stonehearth_ace:ui.game.show_workshop.tooltip_fuel_amount'); });
      
      var satisfactionLevel;
      var servings;
      if (catalogData) {
         App.tooltipHelper.createDynamicTooltip(self.$('.stat.satisfaction'), function () {
            if (satisfactionLevel == null || servings == null) {
               if (catalogData['food_satisfaction']) {
                  satisfactionLevel = 'food.' + stonehearth_ace.getSatisfactionLevel(App.constants.food_satisfaction_thresholds, catalogData['food_satisfaction']);
                  servings = catalogData['food_servings'];
               }
               else if (catalogData['drink_satisfaction']) {
                  satisfactionLevel = 'drink.' + stonehearth_ace.getSatisfactionLevel(App.constants.drink_satisfaction_thresholds, catalogData['drink_satisfaction']);
                  servings = catalogData['drink_servings'];
               }
               else if (catalogData['is_animal_feed']) {
                  satisfactionLevel = 'food.animal';
                  servings = catalogData['food_servings'];
               }
            }

            if (satisfactionLevel && servings) {
               return i18n.t(`stonehearth_ace:ui.game.unit_frame.satisfaction.${satisfactionLevel}`, {servings: servings});
            }
         })
      }
   },

   // ACE: override this function since we're modifying the dynamic tooltip code
   _calculateEquipmentData: function (recipe) {
      var self = this;
      var productCatalogData = App.catalog.getCatalogData(recipe.product_uri);

      if (productCatalogData && (productCatalogData.equipment_required_level || productCatalogData.equipment_roles ||
            productCatalogData.consumable_buffs || productCatalogData.consumable_effects || productCatalogData.consumable_after_effects ||
            productCatalogData.buffs || productCatalogData.injected_buffs || productCatalogData.inflictable_debuffs ||
            productCatalogData.equipment_types || productCatalogData.consumable_buffs || productCatalogData.consumable_effects ||
            productCatalogData.consumable_after_effects || productCatalogData.collision_size || productCatalogData.storage_capacity)) {
         self.$('.detailsView').find('.tooltipstered').tooltipster('destroy');

         var collisionSize = productCatalogData.collision_size && i18n.t('stonehearth_ace:ui.game.unit_frame.collision_size', productCatalogData.collision_size);
         self.set('collisionSize', collisionSize);

         var maxLength = productCatalogData.max_length;
         self.set('maxLength', maxLength);

         var storageCapacity = productCatalogData.storage_capacity;
         self.set('storageCapacity', storageCapacity);

         var fuelCapacity = productCatalogData.fuel_capacity;
         self.set('fuelCapacity', fuelCapacity);

         var warmthRadius = productCatalogData.warmth_radius;
         self.set('warmthRadius', warmthRadius);

         var maxHealth = productCatalogData.max_health;
         self.set('maxHealth', maxHealth);

         var menace = productCatalogData.menace;
         self.set('menace', menace);

         var sightRange = productCatalogData.sight_range;
         self.set('sightRange', sightRange);

         var showEquipment = false;
         if (productCatalogData.equipment_roles) {
            var classArray = stonehearth_ace.findRelevantClassesArray(productCatalogData.equipment_roles);
            self.set('allowedClasses', classArray);
            showEquipment = true;
         }
         else {
            self.set('allowedClasses', null);
         }
         if (productCatalogData.equipment_required_level) {
            self.$('#levelRequirement').text(i18n.t('stonehearth:ui.game.unit_frame.level') + productCatalogData.equipment_required_level);
            showEquipment = true;
         } else {
            self.$('#levelRequirement').text('');
         }
         
         var equipmentTypes = [];
         if (productCatalogData.equipment_types) {
            equipmentTypes = stonehearth_ace.getEquipmentTypesArray(productCatalogData.equipment_types);
            showEquipment = true;
         }
         self.set('equipmentTypes', equipmentTypes);

         self._setBuffsByType(productCatalogData, 'buffs', 'buffs');
         self._setBuffsByType(productCatalogData, 'consumable_buffs', 'consumableBuffs');
         self._setBuffsByType(productCatalogData, 'injected_buffs', 'injectedBuffs');
         self._setBuffsByType(productCatalogData, 'inflictable_debuffs', 'inflictableDebuffs');
         self._setBuffsByType(productCatalogData, 'consumable_effects', 'consumableEffects');
         self._setBuffsByType(productCatalogData, 'consumable_after_effects', 'consumableAfterEffects');

         if (collisionSize) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_size_header')}</span>` +
                  `${i18n.t('stonehearth_ace:ui.game.entities.tooltip_size', productCatalogData.collision_size)}</div>`
            App.guiHelper.addTooltip(self.$('#collisionSize'), description);
         }

         if (maxLength) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_max_length')}</span>` +
                  `<span class="value">${maxLength}</span></div>`;
            App.guiHelper.addTooltip(self.$('#maxLength'), description);
         }

         if (storageCapacity) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_storage_capacity')}</span>` +
                  `<span class="value">${storageCapacity}</span></div>`;
            App.guiHelper.addTooltip(self.$('#storageCapacity'), description);
         }

         if (fuelCapacity) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_fuel_capacity')}</span>` +
                  `<span class="value">${fuelCapacity}</span></div>`;
            App.guiHelper.addTooltip(self.$('#fuelCapacity'), description);
         }

         if (warmthRadius) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_warmth_radius')}</span>` +
                  `<span class="value">${warmthRadius}</span></div>`;
            App.guiHelper.addTooltip(self.$('#warmthRadius'), description);
         }

         if (maxHealth) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_max_health')}</span>` +
                  `<span class="value">${maxHealth}</span></div>`;
            App.guiHelper.addTooltip(self.$('#maxHealth'), description);
         }

         if (menace) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_menace')}</span>` +
                  `<span class="value">${menace}</span></div>`;
            App.guiHelper.addTooltip(self.$('#menace'), description);
         }

         if (sightRange) {
            var description = `<div class="stat"><span class="header">${i18n.t('stonehearth_ace:ui.game.entities.tooltip_sight_range')}</span>` +
                  `<span class="value">${sightRange}</span></div>`;
            App.guiHelper.addTooltip(self.$('#sightRange'), description);
         }

         if (showEquipment) {
            self.$('#equipmentRequirements').show();
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
         }
         else {
            self.$('#equipmentRequirements').hide();
         }

         // make tooltips for inflictable debuffs
         Ember.run.scheduleOnce('afterRender', this, function() {
            self._createBuffTooltips();
         });

         self.$('#leftStats').show();
      } else {
         self.$('#leftStats').hide();
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

      self._createBuffTooltipsByType('buffs', 'buff');
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

   _workshopPausedChange: function() {
      var isPaused = !!(this.get('model.order_list.is_paused'));
      var isSecondaryListPaused = !!(this.get('model.order_list.is_secondary_list_paused'));

      // We need to check this because if/when the root object changes, all children are
      // marked as changed--even if the values don't differ.
      var isPausedDiff = isPaused != this.isPaused;
      var isSecondaryListPausedDiff = isSecondaryListPaused != this.isSecondaryListPaused;
      if (!isPausedDiff && !isSecondaryListPausedDiff) {
         return;
      }
      this.isPaused = isPaused;
      this.isSecondaryListPaused = isSecondaryListPaused;

      this.set('model.workshopIsPaused', isPaused);
      this.set('model.secondaryListIsPaused', isSecondaryListPaused);

      if (isPausedDiff) {
         this._animateStatusSign(this.$("#statusSign"), isPaused);
      }
      if (isSecondaryListPausedDiff) {
         this._animateStatusSign(this.$("#secondaryListStatusSign"), isSecondaryListPaused);
      }
      
   }.observes('model.order_list.is_paused', 'model.order_list.is_secondary_list_paused'),

   _animateStatusSign: function(sign, isPaused) {
      if (sign) {
         sign.animate({
               rot: isPaused ? 4 : -4,
            },
            {
               duration: 200,
               step: function(now,fx) {
                  var percentDone;
                  var end = fx.end;
                  var start = fx.start;

                  if (end > start) {
                     percentDone = (now - start) / (end - start);
                  } else {
                     percentDone = -1 * (now - start) / (start - end);
                  }

                  var scaleX = percentDone < .5 ? 1 - (percentDone * 2) : (percentDone * 2) - 1;
                  $(this).css('-webkit-transform', 'rotate(' + now + 'deg) scale(' + scaleX +', 1)');
               }
         });
      }
   },

   //Attach sortable/draggable functionality to the order
   //list. Hook order list onto garbage can. Set up scroll
   //buttons.
   _buildOrderList: function(orderList, enableTrash){
      var self = this;

      var sortableGarbage = self.makeSortable(orderList.find(".orders, .garbageList"), {
         axis: "y",
         connectWith: orderList.find(".garbageList"),
         beforeStop: function (event, ui) {
            //Called right after an object is dropped
            if(ui.item[0].parentNode && ui.item[0].parentNode.classList.contains("garbageList")) {
               ui.item.addClass("hiddenOrder");
               var id = parseInt(ui.item.attr("data-orderid"))
               radiant.call_obj(self.getOrderList(), 'delete_order_command', id)
                  .done(function(return_data){
                     ui.item.remove();
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:trash'} );
                  });
             }
         },
         over: function (event, ui) {
            //Called whenever we hover over a new target
            if (event.target.id == "garbageList") {
               ui.item.find(".deleteLabel").addClass("showDelete");
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:highlight'} );
            } else {
               ui.item.find(".deleteLabel").removeClass("showDelete");
            }
         },
         start: function(event, ui) {
            // on drag start, creates a temporary attribute on the element with the old index
            $(this).attr('data-previndex', orderList.find(".orderListItem").index(ui.item) + 1);
            self.is_sorting = ui.item[0];
         },
         stop: function(event, ui) {
            //if we're not sorting anymore, don't do anything
            if (self.is_sorting == null) {
               return;
            }
            //Don't update objects inside the garbage list
            if(ui.item[0].parentNode && ui.item[0].parentNode.classList.contains("garbageList")) {
               return;
            }

            //If we're still sorting, then update the order list
            var newPos = orderList.find(".orderListItem").index(ui.item) + 1;
            var id =  parseInt(ui.item.attr("data-orderid"));

            //Check if we're replacing?
            if ($(this).attr('data-previndex') == newPos) {
               return;
            }

            radiant.call_obj(self.getOrderList(), 'change_order_position_command', newPos, id);

            //Let people know we're no longer sorting
            self.is_sorting = null;
         }
      });

      if (sortableGarbage) {
         sortableGarbage.disableSelection();
      }

      self._updateButtonStates(orderList);
      self._enableDisableTrash(orderList, enableTrash);

      orderList.find('.orders').on('scroll', function() {
         // when the user scrolls with the mouse, make sure the scroll buttons are right
         self._scrollOrderList(orderList, null);
      });
   },

   // Update button visibility based on order list height
   _updateButtonStates: function(orderList) {
      var self = this;
      //Set the default state of the buttons
      var orders = orderList.find('.orders');
      var buttons = orderList.find('.scrollButtons');
      if (buttons) {
         var ordersList = orders[0];
         if (ordersList && ordersList.scrollHeight > orders.innerHeight()) {
            self._scrollOrderList(orderList, 0);
         } else {
            buttons.find('.orderListUpBtn').hide();
            buttons.find('.orderListDownBtn').hide();
         }
      }
   },

   _scrollOrderList: function(orderList, amount) {
      var orders = orderList.find('.orders');
      var buttons = orderList.find('.scrollButtons');
      var newScrollTop = Math.max(orders.scrollTop() + (amount || 0), 0);
      if (newScrollTop === 0) {
         // top of list
         buttons.find('.orderListUpBtn').hide();
         buttons.find('.orderListDownBtn').show();
      } else if (newScrollTop + orders.innerHeight() >= orders[0].scrollHeight) {
         // bottom of list
         buttons.find('.orderListUpBtn').show();
         buttons.find('.orderListDownBtn').hide();
      } else {
         buttons.find('.orderListUpBtn').show();
         buttons.find('.orderListDownBtn').show();
      }

      if (amount != null) {
         orders.animate({scrollTop: newScrollTop}, 100);
      }
   },

   _onOrdersUpdated: function () {
      var self = this;
      if (!self.get('isVisible')) return;
      self._updatedOrders(self.$('#orderList'), self.get('model.order_list.orders'));
      Ember.run.scheduleOnce('afterRender', self, '_updateOrdersInDetailedOrderList');
   }.observes('model.order_list.orders'),

   _onSecondaryOrdersUpdated: function () {
      var self = this;
      if (!self.get('isVisible')) return;
      self._updatedOrders(self.$('#secondaryOrderList'),
            (self.get('model.order_list.secondary_orders') || []).concat(self.get('model.order_list.auto_craft_orders') || []));
      Ember.run.scheduleOnce('afterRender', self, '_updateSecondaryOrdersInDetailedOrderList');
   }.observes('model.order_list.secondary_orders', 'model.order_list.auto_craft_orders'),

   _updatedOrders: function (orderList, orders) {
      var self = this;

      //If we're sorting as an order completes, cancel the sorting
      //or when the order list updates, the sortable element complains
      if (self.is_sorting != null) {
         var orderID = self.is_sorting.getAttribute("data-orderID");
         var sortedOrder = self.is_sorting;

         self.is_sorting = null;
         orderList.find(".orders, .garbageList").sortable("cancel");
         self.$('#orderListContainer table').sortable("cancel");

         //If we were sorting the very thing that got deleted in this update, we
         //need to remove it from the order list because the cancel will have re-added it.
         //Note: this makes me feel  dirty. I mean, why doesn't ember/handlebars
         //wipe the re-added thing when the UI updates? These 2 frameworks DO play together
         //they just feel like they're having an ideological argument IN OUR CODE.
         var found = false;
         for (i = 0; i < orders.length; i++) {
            if (orders[i].id == orderID) {
               found = true;
               break;
            }
         }
         if (found || $(sortedOrder).hasClass('inProgressOrder')) {
            //The thing we're sorting is no longer here or a new copy has been made; Remove it.
            $(sortedOrder).remove();
         }
      }

      self._enableDisableTrash(orderList, orders && orders.length > 0);
   },

   _enableDisableTrash: function (orderList, enable) {
      var garbageButton = orderList.find('.garbageButton');
      if (garbageButton) {
         if (enable) {
            garbageButton.css('opacity', '1');
         } else {
            garbageButton.css('opacity', '0.3');
         }
      }
   },

   _onOrderCountUpdated: function () {
      var self = this;
      if (!self.get('isVisible')) return;
      var orderCount = self.get('model.order_list.orders.length');
      if (orderCount) {
         var craftButton = self.$('#craftButtonLabel');
         var craftButtonImage = self.$('#craftButtonImage');
         if (!craftButtonImage) return;
         if (orderCount >= self.maxActiveOrders) {
            craftButtonImage.css('-webkit-filter', 'grayscale(100%)');
            craftButton.addClass('disabled');
            self.set('craft_button_text', 'stonehearth:ui.game.show_workshop.craft_queue_full');
         } else {
            craftButtonImage.css('-webkit-filter', 'grayscale(0%)');
            craftButton.removeClass('disabled');
            self.set('craft_button_text', 'stonehearth:ui.game.show_workshop.craft');
         }
      }
   }.observes('model.order_list.orders.length'),
   
   orderTypeName: function () { return this.get('uri').replace(/\W/g, '') + '-orderType'; }.property('uri'),
   orderTypeMakeId: function () { return this.get('uri').replace(/\W/g, '') + '-make'; }.property('uri'),
   orderTypeMaintainId: function () { return this.get('uri').replace(/\W/g, '') + '-maintain'; }.property('uri'),
   searchTitleCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-title'; }.property('uri'),
   searchDescriptionCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-description'; }.property('uri'),
   searchIngredientsCheckboxId: function () { return this.get('uri').replace(/\W/g, '') + '-search-ingredients'; }.property('uri')
});

$(document).ready(function () {
   App.workshopManager.init();

   // Show the crafting UI from the workshops, and from the crafter.
   $(top).on("radiant_show_workshop", function (_, e) {
      App.workshopManager.toggleWorkshop(e.event_data.crafter_type);
   });
   $(top).on("radiant_show_workshop_from_crafter", function (_, e) {
      App.workshopManager.toggleWorkshop(e.event_data.crafter_type);
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
});

$(top).on('stonehearthReady', function() {
   // need to apply the settings on load as well
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_selected_workshop_crafting', function(value) {
      $(top).trigger('show_selected_workshop_crafting_changed', { value: value });
   });
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'default_craft_search_checks', function(value) {
      $(top).trigger('default_craft_search_checks_changed', { value: value });
   });
});
