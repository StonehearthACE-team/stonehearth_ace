// ACE: added event for showing a shop bulletin from a merchant/stall
$(top).on('stonehearth_ace_show_shop', function(_, e) {
   // instead of calling a command to show a bulletin by default, first fire this event
   // check to see if the bulletin already exists
   // if it exists and is currently being shown, simply dismiss it
   // if it exists and isn't being shown, show it (do we need to dismiss other existing shop bulletins?)
   // if it doesn't exist, dismiss other existing shop bulletins and call the command function
   radiant.call_obj('stonehearth_ace.mercantile', 'get_shop_command', e.entity)
      .done(function(response) {
         if (response.shop) {
            var shopBulletin;
            radiant.each(App.bulletinBoard._bulletins, function(_, bulletin) {
               if (bulletin.type == 'shop') {
                  var shop = bulletin.data && bulletin.data.shop;
                  if (shop == response.shop) {
                     shopBulletin = bulletin;
                  }
               }
            });

            // first close any existing (shop?) bulletins that aren't this one
            App.bulletinBoard.closeDialogView(function(data) {
               return !shopBulletin || data.id != shopBulletin.id;
            });

            if (shopBulletin) {
               App.bulletinBoard.tryShowBulletin(shopBulletin);
            }
            else {
               radiant.call_obj('stonehearth_ace.mercantile', 'show_shop_command', e.entity);
            }
         }
      });
});

// ACE: added concept of "wanted items" to merchants
// as well as unwanted (generally what they're already selling)
App.StonehearthShopBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'shopBulletinDialog',
   components : {
      data : {
         shop : {
            sellable_items : {
               "tracking_data" : {}
            },
            shop_inventory : {
               "*" : {}
            }
         }
      }
   },

   // sellable item trace is very expensive and shop dialogs can stack up when hidden
   // so just destroy this dialog and recreate when dialog is re-opened from bulletin list
   SHOULD_DESTROY_ON_HIDE_DIALOG: true,

   _traceInventoryGold: function() {
      let self = this;
      self.set('gold', 0);
      radiant.call_obj('stonehearth.inventory', 'get_inventory_command')
         .done(function (response) {
            self._gold_trace = new StonehearthDataTrace(response.result, {})
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  self.set('gold', response.read_only_gold_amount);
                  self._updateBuyButtons();
                  self._updateSellButtons();
               });
         });
   },

   willDestroyElement: function() {
      if (this._gold_trace && this._gold_trace.destroy) {
         this._gold_trace.destroy();
         delete this._gold_trace;
      }
      this._buyPalette.stonehearthItemPalette('destroy');
      this._sellPalette.stonehearthItemPalette('destroy');

      this.$().find('.tooltipstered').tooltipster('destroy');

      this.$().off('click', '#sellList .row');
      this.$().off('click', '.wantedItem');

      this.$('#buy1Button').off('click');
      this.$('#buy10Button').off('click');
      this.$('#buyAllButton').off('click');
      this.$('#sell1Button').off('click');
      this.$('#sell10Button').off('click');
      this.$('#sellAllButton').off('click');
      this._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      // build the inventory palettes
      self._buildBuyPalette();
      self._buildSellPalette();

      self.$('#buy1Button').tooltipster();
      self.$('#buy10Button').tooltipster();
      self.$('#buyAllButton').tooltipster();
      self.$('#sell1Button').tooltipster();
      self.$('#sell10Button').tooltipster();
      self.$('#sellAllButton').tooltipster();

      self.$().on('click', '#sellList .row', function() {
         self.$('#sellList .row').removeClass('selected');
         var row = $(this);

         row.addClass('selected');
         //self._selectedUri = row.attr('uri');

         self._updateSellButton();
      });

      self.$('#buy1Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._doBuy(1);
         }
      });

      self.$('#buy10Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._doBuy(10);
         }
      });
      self.$('#buyAllButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            var allCount = self.$('#buyList .selected .num').text()
            self._doBuy(Number(allCount));
         }
      });

      self.$('#sell1Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._doSell(1);
         }
      });

      self.$('#sell10Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._doSell(10);
         }
      });

      self.$('#sellAllButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            var allCount = self.$('#sellList .selected .num').text();
            self._doSell(Number(allCount));
         }
      });

      self.$().on('click', '.wantedItem', function() {
         var el = $(this);
         var wantedItems = self.get('wantedItems');
         var wantedItem = wantedItems && wantedItems[el.attr('data-index')];
         if (wantedItem != null) {
            // try to scroll to and select the first owned item matching this
            self._scrollSellPalette(wantedItem);
         }
         return false;
      });

      self._traceInventoryGold();
      self._updateBuyButtons();
      self._updateSellButtons();
      self._updateInventory();
      self._updateSellableItems();
      this.$('#buyTab').show();
   },

   _buildBuyPalette: function() {
      var self = this;

      this._buyPalette = this.$('#buyList').stonehearthItemPalette({
         cssClass: 'shopItem',
         isBuying: true,
         itemAdded: function(itemEl, itemData) {
            itemEl.attr('cost', itemData.cost);
            itemEl.attr('num', itemData.num);

            $('<div>')
               .addClass('cost')
               .html(itemData.cost + 'g')
               .appendTo(itemEl);

         },
         click: function(item, e) {
            self._updateBuyButtons();
         },
         rightClick: function (item, e) {
            self._updateBuyButtons();
            self._doBuy(1);
         }
      });
   },

   _updateInventory: function() {
      if (!this.$()) {
         return;
      }
      var shop_inventory = this.get('model.data.shop.shop_inventory');
      this._buyPalette.stonehearthItemPalette('updateItems', shop_inventory);
   }.observes('model.data.shop.shop_inventory'),

   _updateSellableItems: function() {
      if (!this.$()) {
         return;
      }
      var tracking_data = this.get('model.data.shop.sellable_items.tracking_data');
      var sellable_items = {}
      radiant.each(tracking_data, function(uri, uri_entry) {
         radiant.each(uri_entry.item_qualities, function(item_quality_key, data) {
            data.uri = uri_entry.uri;
            // The key's purpose is just to make sure each entry with a different item quality is unique
            var key = data.uri + '&item_quality=' + item_quality_key;
            sellable_items[key] = data;
         });
      });
      this._sellPalette.stonehearthItemPalette('updateItems', sellable_items);
   }.observes('model.data.shop.sellable_items'),

   _updateShopDescription: function() {
      var self = this;
      var description = self.get('model.data.shop.description');
      var description_i18n_data = self.get('model.data.shop.description_i18n_data');
      self.set('hasShopDescription', description != null);
      self.set('shopDescription', i18n.t(description, description_i18n_data));
   }.observes('model.data.shop.description'),

   _updateWantedItems: function() {
      if (!this.$()) {
         return;
      }
      var self = this;
      var wantedItems = self.get('model.data.shop.wanted_items');
      if (wantedItems != null && (!wantedItems.length || wantedItems.length == 0)) {
         wantedItems = null;
      }
      self._sellPalette.stonehearthItemPalette('updateWantedItems', wantedItems);

      if (wantedItems != null) {
         var items = [];
         wantedItems.forEach(item => {
            var icon, display_name, category;
            if (item.uri) {
               var catalogData = App.catalog.getCatalogData(item.uri);
               if (catalogData == null) return;
               icon = catalogData.icon;
               display_name = catalogData.display_name;
               category = catalogData.category;
            }
            else if (item.material) {
               var resource = App.resourceConstants.resources[item.material];
               if (resource == null) return;
               icon = resource.icon;
               display_name = resource.name;
               category = 'resources';
            }

            var priceMod = Math.floor((item.price_factor - 1) * 100 + 0.5);
            var isHigher = priceMod > 0;
            var isLower = priceMod < 0;

            items.push({
               maxQuantity: item.max_quantity,
               quantity: item.quantity,
               index: items.length,
               uri: item.uri,
               material: item.material,
               icon: icon,
               display_name: display_name,
               category: category,
               isAvailable: item.max_quantity == null || item.max_quantity > item.quantity,
               isHigher: isHigher,
               isLower: isLower,
               priceMod: priceMod,
               factor: isHigher ? `+${priceMod}%` : (isLower ? `${priceMod}%` : null),
               num: `${item.quantity} / ${item.max_quantity == null ? '∞' : item.max_quantity}`,
            });
         });
         self.set('wantedItems', items);
         self.set('hasWantedItems', true);
      }
      else {
         self.set('wantedItems', null);
         self.set('hasWantedItems', false);
      }

      Ember.run.scheduleOnce('afterRender', self, function () {
         var wantedItems = self.$('.wantedItem');
         if (wantedItems) {
            wantedItems.each(function () {
               var el = $(this);
               var wantedItems = self.get('wantedItems');
               var wantedItem = wantedItems && wantedItems[el.attr('data-index')];
               if (wantedItem != null) {
                  // add a tooltip
                  App.tooltipHelper.createDynamicTooltip(el, function() {
                     var description = wantedItem.category && i18n.t('stonehearth:ui.game.entities.item_categories.' + wantedItem.category);
                     var quantity = wantedItem.maxQuantity != null ? (wantedItem.maxQuantity - wantedItem.quantity) : null;
                     var hasQuantity = quantity != null;
                     // show the percentage modification to the price
                     var priceMod = wantedItem.priceMod;
                     if (priceMod > 0) {
                        // price is increased
                        description += '<div class="wantedItem">' +
                              i18n.t('stonehearth_ace:ui.game.entities.tooltip_wanted_item_higher' + (hasQuantity ? '_quantity' : ''),
                                 {
                                    factor: priceMod,
                                    quantity: quantity
                                 }) + '</div>';
                     }
                     else if (priceMod < 0) {
                        // price is decreased!
                        description += '<div class="wantedItem">' +
                              i18n.t('stonehearth_ace:ui.game.entities.tooltip_wanted_item_lower' + (hasQuantity ? '_quantity' : ''),
                                 {
                                    factor: Math.abs(priceMod),
                                    quantity: quantity
                                 }) + '</div>';
                     }
                     return $(App.tooltipHelper.createTooltip(i18n.t(wantedItem.display_name), description));
                  });
               }
            });
         }
      });
   }.observes('model.data.shop.wanted_items'),

   _buildSellPalette: function() {
      var self = this;

      self._sellPalette = self.$('#sellList').stonehearthItemPalette({
         cssClass: 'shopItem',
         wantedItems: self.get('model.data.shop.wanted_items'),
         itemAdded: function(itemEl, itemData) {
            itemEl.attr('cost', itemData.resale );
            itemEl.attr('num', itemData.num);

            $('<div>')
               .addClass('cost')
               .html(itemData.resale + 'g')
               .appendTo(itemEl);

         },
         updateWantedItem: function(itemEl, priceFactor) {
            var cost = Math.max(1, Math.floor(itemEl.attr('cost') * priceFactor + 0.5));
            itemEl.find('.cost').html(cost + 'g');
            
            if (itemEl.hasClass('selected')) {
               self._updateSellButtons();
            }
         },
         click: function(item, e) {
            self._updateSellButtons();
         },
         rightClick: function (item, e) {
            self._updateSellButtons();
            self._doSell(1);
         },
         showSearchFilter: true,
      });
      self._sellPalette.stonehearthItemPalette('showSearchFilter');
   },

   _updateSoldItems: function() {
      this._sellPalette.stonehearthItemPalette('updateSoldItems', this.get('model.data.shop.shop_inventory'));
   }.observes('model.data.shop.shop_inventory'),

   _scrollSellPalette: function(item) {
      // .shopItem elements in the palette will already be marked as wantedItem if they're wanted
      // we could filter on that instead, but then it would stop working when they're no longer wanted
      var self = this;
      var shopItems = self.$('#sellList .shopItem').toArray();
      var foundItem = null;
      for (var i = 0; i < shopItems.length; i++) {
         var shopItem = $(shopItems[i]);
         var uri = shopItem.attr('uri');
         if (item.uri == uri) {
            foundItem = shopItem;
            break;
         }
         else if (item.material != null) {
            var catalogData = App.catalog.getCatalogData(uri);
            if (radiant.isMaterial(catalogData.materials, item.material)) {
               foundItem = shopItem;
               break;
            }
         }
      }

      if (foundItem != null) {
         var sellPalette = self.$('#sellList');
         var scrollPos = foundItem.offset().top - 500;
         sellPalette.animate({
            scrollTop: '+=' + scrollPos
         }, 250);
         //foundItem.get(0).scrollIntoView({behavior: "smooth", block: "center"}); // options don't work in this old version of chrome
         //self.$('#sellList').scrollTo(foundItem);
         foundItem.click();
      }
   },

   _doBuy: function(quantity) {
      var self = this;
      var shop = self.get('model.data.shop');
      var selected = self.$('#buyList .selected')
      var uri = selected.attr('uri');
      var quality = parseInt(selected.attr('item_quality'));

      radiant.call_obj(shop, 'buy_item_command', uri, quality, quantity)
         .done(function() {
            // play a 'chaching!' noise or something
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:shop_buy'} )
         })
         .fail(function() {
            // play a 'bonk!' noise or something
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:shop_negative'} )
         })
   },

   _doSell: function(quantity) {
      var self = this;
      var shop = self.get('model.data.shop');
      var selected = self.$('#sellList .selected')
      var uri = selected.attr('uri');
      var quality = parseInt(selected.attr('item_quality'));
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:shop_sell'} )

      if (!uri) {
         return;
      }

      radiant.call_obj(shop, 'sell_item_command', uri, quality, quantity)
         .fail(function() {
            // play a 'bonk!' noise or something
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:shop_negative'} )
         })
   },

   _updateBuyButtons: function() {
      var self = this;

      var item = self.$('#buyList').find(".selected");
      var cost = parseInt(item.attr('cost'));
      // For some reason, if there's nothing selected
      // item will still be defined, but its cost will be NaN.
      if (item && cost) {
         // update the buy buttons
         var gold = self.get('gold');

         if (cost <= gold) {
            self._enableButton('#buy1Button');
            self._enableButton('#buy10Button');
            self._enableButton('#buyAllButton');
         } else  {
            self._disableButton('#buy1Button', 'stonehearth:ui.game.bulletin.shop.not_enough_gold_tooltip');
            self._disableButton('#buy10Button', 'stonehearth:ui.game.bulletin.shop.not_enough_gold_tooltip');
            self._disableButton('#buyAllButton', 'stonehearth:ui.game.bulletin.shop.not_enough_gold_tooltip');
         }
      } else {
         self._disableButton('#buy1Button');
         self._disableButton('#buy10Button');
         self._disableButton('#buyAllButton');
      }
   },

   _updateSellButtons: function() {
      var self = this;

      var item = self.$('#sellList .selected')
      var costStr = item.find('cost').html();
      var cost = costStr && parseInt(costStr.substr(0, costStr.length - 1)); // trim off the 'g' at the end

      if (!item || item.length == 0) {
         self._disableButton('#sell1Button');
         self._disableButton('#sell10Button');
         self._disableButton('#sellAllButton');
      } else {
         var gold = self.get('model.data.shop.shopkeeper_gold');
         if (cost && (cost > gold)) {
            self._disableButton('#sell1Button', 'stonehearth:ui.game.bulletin.shop.shopkeeper_not_enough_gold_tooltip');
            self._disableButton('#sell10Button', 'stonehearth:ui.game.bulletin.shop.shopkeeper_not_enough_gold_tooltip');
            self._disableButton('#sellAllButton', 'stonehearth:ui.game.bulletin.shop.shopkeeper_not_enough_gold_tooltip');
         } else {
            self._enableButton('#sell1Button');
            self._enableButton('#sell10Button');
            self._enableButton('#sellAllButton');
         }
      }
   },

   _disableButton: function(buttonId, tooltipId) {
      // Disable the button with a tooltip if provided.
      self.$(buttonId).addClass('disabled');
      if (tooltipId) {
         self.$(buttonId).tooltipster('content', i18n.t(tooltipId));
         self.$(buttonId).tooltipster('enable');
      } else {
         self.$(buttonId).tooltipster('disable');
      }
   },

   _enableButton: function(buttonId) {
      self.$(buttonId).removeClass('disabled');
      self.$(buttonId).tooltipster('disable');
   },

});
