App.StonehearthTownView.reopen({
   lastClickedUri: null,
   lastClickedItem: null,

   didInsertElement: function () {
      var self = this;
      self._super();

      self._inventoryPalette = self.$('#inventoryPalette').stonehearthItemPalette({
         cssClass: 'inventoryItem',
         click: function (item) {
               // when the player clicks an inventory item, we want to try to select and go to that item
               // check if this was the last clicked item; if so, and it has count > 1, lookup "next" actual item for it
               var uri = item.attr('uri');
               var item_quality = item.attr('item_quality');
               var items = self.getItemsFromUri(uri, item_quality);
               if (items.length > 0) {
                  if (uri != self.lastClickedUri) {
                     self.lastClickedUri = uri;
                     self.lastClickedItem = null;
                  }
                  var nextItem = 0;
                  if (self.lastClickedItem) {
                     nextItem = (items.indexOf(self.lastClickedItem) + 1) % items.length;
                  }
                  self.lastClickedItem = items[nextItem];

                  radiant.call('towninventorytracker:get_item_container', self.lastClickedItem)
                     .done(function(response) {
                        var camera_focus = self.lastClickedItem;
                        if (response.container && response.container != '') {
                           camera_focus = response.container;
                        }
                        // select and focus on the container if the item is in one (otherwise select and focus the item)
                        radiant.call('stonehearth:select_entity', camera_focus);
                        radiant.call('stonehearth:camera_look_at_entity', camera_focus);
                     });
               }
         }
      });
   },

   getItemsFromUri: function (this_uri, this_quality) {
      var self = this;
      var items = [];

      if (this_uri) {
         this_uri = this_uri.replace('.', '&#46;');
         var canonical_uri = self._inventoryTrackingData[this_uri].canonical_uri;
         if (!canonical_uri) {
            canonical_uri = this_uri;
         }
         radiant.each(self._inventoryTrackingData, function (_, uri_entry) {
            if (canonical_uri == uri_entry.uri || canonical_uri == uri_entry.canonical_uri) {
               radiant.each(uri_entry.item_qualities, function (item_quality_key, item_of_quality) {
                  if (item_quality_key == this_quality) {
                     radiant.each(item_of_quality.items, function (_, item) {
                        items.push(item);
                     });
                  }
               });
            }
         });
      }

      return items;
   }
});