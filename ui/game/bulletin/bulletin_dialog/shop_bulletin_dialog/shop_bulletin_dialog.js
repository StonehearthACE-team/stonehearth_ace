App.StonehearthShopBulletinDialog.reopen({
   _updateWantedItems: function() {
      if (!this.$()) {
         return;
      }
      var wantedItems = this.get('model.data.shop.wanted_items');
      if (wantedItems != null && wantedItems.length == 0) {
         wantedItems = null;
      }
      this._sellPalette.stonehearthItemPalette('updateWantedItems', wantedItems);

      if (wantedItems != null) {
         var items = [];
         wantedItems.forEach(item => {
            var icon;
            if (item.uri) {
               var catalogData = App.catalog.getCatalogData(item.uri);
               if (catalogData == null) return;
               icon = catalogData.icon;
            }
            else if (item.material) {
               var resource = App.resourceConstants.resources[item.material];
               if (resource == null) return;
               icon = resource.icon;
            }

            var priceMod = Math.floor((item.price_factor - 1) * 100 + 0.5);
            var isHigher = priceMod > 0;
            var isLower = priceMod < 0;

            items.push({
               icon: icon,
               isAvailable: item.max_quantity == null || item.max_quantity > item.quantity,
               isHigher: isHigher,
               isLower: isLower,
               factor: isHigher ? `+${priceMod}%` : (isLower ? `${priceMod}%` : null),
               num: `${item.quantity} / ${item.max_quantity == null ? '∞' : item.max_quantity}`,
            });
         });
         this.set('wantedItems', items);
         this.set('hasWantedItems', true);
      }
      else {
         this.set('wantedItems', null);
         this.set('hasWantedItems', false);
      }

      // also set up some tooltips for these? using Ember.run.scheduleOnce('afterRender') or whatever it is
   }.observes('model.data.shop.wanted_items'),

   _buildSellPalette: function() { // ACE MODIFIED
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
});

