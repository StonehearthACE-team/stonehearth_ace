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

App.StonehearthShopBulletinDialog.reopen({
   willDestroyElement: function() {
      this.$().off('click', '.wantedItem');
      this._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

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
   },

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

      this._sellPalette = this.$('#sellList').stonehearthItemPalette({
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
         }
      });
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
});

