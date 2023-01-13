var GOLD_URI = 'stonehearth:loot:gold';

App.StonehearthReembarkationBulletinDialog.reopen({
   didInsertElement: function() {
      this._super();
      var self = this;

      self._srcItemPalette.stonehearthItemPalette('showSearchFilter');
   },

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
            if (catalogData && catalogData.reembark_version) { // added nil check; should only matter if your inventory tracker is messed up
               radiant.each(uriEntry.item_qualities, function (itemQualityKey, item) {
                  var key = catalogData.reembark_version + App.constants.item_quality.KEY_SEPARATOR + itemQualityKey;
                  srcItems[key] = radiant.shallow_copy(uriEntry);
                  srcItems[key].uri = catalogData.reembark_version;
                  // ACE changed this line:
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

App.StonehearthReembarkationBulletinRowView.reopen({
   ace_components: {
      'stonehearth:pet_owner': {
         'pets': {
            '*': {
               'stonehearth:unit_info': {},
            },
         },
      },
   },

   init: function() {
      var self = this;
      stonehearth_ace.mergeInto(self.components, self.ace_components);

      self._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      App.tooltipHelper.createDynamicTooltip(self.$('.hasPetsIcon'), function () {
         var pets = self.get('model.stonehearth:pet_owner.pets');
         var petsArr = [];
         radiant.each(pets, function(_, pet) {
            var petUri = pet.uri;
            var catalogData = App.catalog.getCatalogData(petUri);
            var unit_info = pet['stonehearth:unit_info'];
            var name = unit_info && i18n.t(unit_info.display_name, {self: pet}) || catalogData.display_name;
            petsArr.push({
               name: name,
               icon: catalogData.icon,
               species: i18n.t(catalogData.species_name),
            });
         });

         if (petsArr.length > 0) {
            var description = '<table>';
            petsArr.forEach(pet => {
               description += `<tr><td><img class='reembarkPetImg' src='${pet.icon}'/></td><td class='reembarkPetInfo'><div class='reembarkPetName'>${pet.name}</div><div class='reembarkPetSpecies'>${pet.species}</div></td></tr>`;
            });
            description += '</table>'

            return $(App.tooltipHelper.createTooltip(i18n.t(`stonehearth_ace:ui.game.bulletin.reembarkation.pets`), description));
         }
      });
   },

   _updatePets: function() {
      var self = this;
      var pets = self.get('model.stonehearth:pet_owner.pets');

      self.set('hasPets', pets && radiant.map_to_array(pets).length > 0);
   }.observes('model.stonehearth:pet_owner.pets')
});
