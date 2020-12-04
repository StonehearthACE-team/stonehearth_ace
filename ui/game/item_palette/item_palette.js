// "reopen" the existing widget
$.widget( "stonehearth.stonehearthItemPalette", $.stonehearth.stonehearthItemPalette, {

   options: {
      showZeroes: false,
      skipCategories: false,
      sortField: 'display_name'
   },

   updateItems: function(itemMap) {
      var self = this;

      // Start off with all items marked as not updated.
      var updated = {
         items: {},
         categories: {},
      };

      // Convert item entries for display.
      var arr = radiant.map_to_array(itemMap, function(k, v){
         var uri = self._getUri(v);
         if (uri) {
            var catalogData = App.catalog.getCatalogData(uri);
            // only include an item that has an icon
            if (catalogData && catalogData.icon) {
               v.display_name = catalogData.display_name;
               v.description = catalogData.description;
               v.category = v.category || catalogData.category;   // don't override a manually supplied category
               v.icon = catalogData.icon;
               v.item_quality = v.item_quality || 1;
               v.deprecated = catalogData.deprecated;
               return v;
            }
         }
         return false;  // Skip items with no URI or catalog data.
      });

      // Sort all items globally. This ensures they are sorted within their categories on first add (but not subsequent ones).
      var sortField = self.options.sortField;
      arr.sort(function(a, b){
         var aName = a[sortField];
          var bName = b[sortField];
          if (aName > bName) {
            return 1;
          }
          if (aName < bName) {
            return -1;
          }
          // a must be equal to b
          return 0;
      });

      // Go through each item and update the corresponding DOM element for it.
      radiant.each(arr, function(i, item) {
         var itemCount = self._getCount(item);
         if (self.options.filter(item) && (self.options.showZeroes || itemCount > 0)) {
            var uri = self._getUri(item);
            var itemQuality = item.item_quality;
            var itemCategory = item.category;

            var itemElement = self._itemElements[uri] && self._itemElements[uri][itemQuality];
            var parent = self.palette;

            if (!self.options.skipCategories) {
               var categoryElement = self._categoryElements[itemCategory];

               if (!categoryElement) {
                  categoryElement = self._addCategoryForItem(item);
                  self._categoryElements[itemCategory] = categoryElement
               }
               parent = categoryElement.find('.downSection');
            }

            if (!itemElement) {
               var itemElements = self._itemElements[uri];
               if (!itemElements) {
                  self._itemElements[uri] = {};
               }
               itemElement = self._addItemElement(item)
               self._itemElements[uri][itemQuality] = itemElement;
               parent.append(itemElement);
            }

            self._updateItemElement(itemElement, item, uri);

            updated.categories[item.category] = true;
            if (!updated.items[uri]) updated.items[uri] = {};
            updated.items[uri][itemQuality] = true;
         }
      })

      // Anything that is not marked as updated needs to be removed.
      radiant.each(self._itemElements, function(uri, itemQualities) {
         radiant.each(itemQualities, function(quality, el) {
            if (el != null && !(updated.items[uri] && updated.items[uri][quality])) {
               App.tooltipHelper.removeDynamicTooltip(el);
               el.remove();
               if (self._itemElements[uri]) {
                  self._itemElements[uri][quality] = null;
               }
            }
         });
      });

      radiant.each(self._categoryElements, function(category, el) {
         if (el != null && !updated.categories[category]) {
            App.tooltipHelper.removeDynamicTooltip(el);
            el.remove();
            self._categoryElements[category] = null;
         }
      });
   },

   _updateItemElement: function(itemEl, item, uri) {
      if (!this.options.hideCount) {
         var num = this._getCount(item);

         if (num == 0 && !this.options.showZeroes) {
            App.tooltipHelper.removeDynamicTooltip(itemEl);

            // Remove from item elements map
            if (self._itemElements[uri]) {
               delete self._itemElements[uri][item.quality];
            }
         } else {
            if (!num && !this.options.showZeroes) {
               itemEl.find('.num').html('');
            } else {
               itemEl.find('.num').html(num);
            }
         }
      }

      this._updateItemTooltip(itemEl, item);
   }
});
