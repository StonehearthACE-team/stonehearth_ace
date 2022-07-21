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
      if (wantedItems != null && wantedItems.length == 0) {
         wantedItems = null;
      }
      self._sellPalette.stonehearthItemPalette('updateWantedItems', wantedItems);

      if (wantedItems != null) {
         var items = [];
         wantedItems.forEach(item => {
            var icon, display_name;
            if (item.uri) {
               var catalogData = App.catalog.getCatalogData(item.uri);
               if (catalogData == null) return;
               icon = catalogData.icon;
               display_name = catalogData.display_name;
            }
            else if (item.material) {
               var resource = App.resourceConstants.resources[item.material];
               if (resource == null) return;
               icon = resource.icon;
               display_name = resource.name;
            }

            var priceMod = Math.floor((item.price_factor - 1) * 100 + 0.5);
            var isHigher = priceMod > 0;
            var isLower = priceMod < 0;

            items.push({
               index: items.length,
               uri: item.uri,
               material: item.material,
               icon: icon,
               display_name: display_name,
               isAvailable: item.max_quantity == null || item.max_quantity > item.quantity,
               isHigher: isHigher,
               isLower: isLower,
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
         self.$('.wantedItem').each(function () {
            var el = $(this);
            var wantedItems = self.get('wantedItems');
            var wantedItem = wantedItems && wantedItems[el.attr('data-index')];
            if (wantedItem != null) {
               // add a tooltip
               App.tooltipHelper.createDynamicTooltip(el, function() {
                  return $(App.tooltipHelper.createTooltip(i18n.t(wantedItem.display_name)));
               });
            }
         });
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
         updateWantedItem: function(itemEl, wantedItem) {
            var cost = Math.floor(itemEl.attr('cost') * (wantedItem && wantedItem.price_factor || 1) + 0.5);
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
      var cost = parseInt(costStr.substr(0, costStr.length - 1)); // trim off the 'g' at the end

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

