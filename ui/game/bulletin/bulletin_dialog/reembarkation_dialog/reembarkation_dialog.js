var GOLD_URI = 'stonehearth:loot:gold';

App.StonehearthReembarkationBulletinDialog.reopen({
   _updateItems: function () {
      var self = this;
      var srcItems = {};

      // Recreate the sellable item list.
      radiant.each(self.get('sellableItemsTrackingData'), function (uriKey, uriEntry) {
         radiant.each(uriEntry.item_qualities, function (itemQualityKey, item) {
            var key = uriEntry.uri + App.constants.item_quality.KEY_SEPARATOR + itemQualityKey;
            srcItems[key] = radiant.shallow_copy(uriEntry);
            srcItems[key].count = item.count;
            srcItems[key].item_quality = itemQualityKey;
         });
      });

      // Add gold and special town bonus "items".
      radiant.each(self.get('ownedItemsTrackingData'), function (uriKey, uriEntry) {
         if (uriKey == GOLD_URI) {
            var goldCount = 0;
            radiant.each(uriEntry.items, function (_, item) {
               goldCount += item['stonehearth:stacks'].stacks;
            });
            var goldBagsCount = Math.floor(goldCount / App.constants.reembarkation.gold_per_bag);
            var key = uriEntry.uri + App.constants.item_quality.KEY_SEPARATOR + '1';
            if (goldBagsCount > 0) {
               srcItems[key] = radiant.shallow_copy(uriEntry);
               srcItems[key].count = goldBagsCount;
               srcItems[key].item_quality = 1;

               srcItems[key].items = {};
               var itemKey = Object.keys(uriEntry.items)[0]
               srcItems[key].items[itemKey] = radiant.shallow_copy(uriEntry.items[itemKey]);
               srcItems[key].items[itemKey]['stonehearth:stacks'].stacks = App.constants.reembarkation.gold_per_bag;
            }
         } else {
            var catalogData = App.catalog.getCatalogData(uriEntry.uri);
            if (catalogData.reembark_version) {
               radiant.each(uriEntry.item_qualities, function (itemQualityKey, item) {
                  var key = (uriEntry.canonical_uri || uriEntry.uri) + App.constants.item_quality.KEY_SEPARATOR + itemQualityKey;
                  srcItems[key] = radiant.shallow_copy(uriEntry);
                  srcItems[key].uri = catalogData.reembark_version;
                  // ACE only changed this line:
                  srcItems[key].count = catalogData.reembark_max_count ? Math.min(item.count, catalogData.reembark_max_count) : 1;
                  srcItems[key].item_quality = itemQualityKey;
               });
            }
         }
      });

      // Remove dstItems that are no longer valid.
      var dstItems = self.get('dstItems');
      radiant.each(dstItems, function (key, entry) {
         if (!srcItems[key]) {
            delete dstItems[key];
         } else {
            var count = Math.min(srcItems[key].count, dstItems[key].count);
            dstItems[key].count = count;
            srcItems[key].count -= count;
            if (srcItems[key].count == 0) {
               delete srcItems[key];
            }
         }
      });

      self.set('srcItems', srcItems);
      self.set('dstItems', dstItems);
      self.notifyPropertyChange('srcItems');
      self.notifyPropertyChange('dstItems');
   }.observes('sellableItemsTrackingData', 'ownedItemsTrackingData')
});
