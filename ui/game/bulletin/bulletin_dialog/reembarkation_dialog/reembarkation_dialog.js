var GOLD_URI = 'stonehearth:loot:gold';

App.StonehearthReembarkationBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'reembarkationBulletinDialog',

   SHOULD_DESTROY_ON_HIDE_DIALOG: true,

   init: function() {
      this._super();
      var self = this;
      self.set('srcCitizens', []);
      self.set('dstCitizens', []);
      self.set('maxDstCitizens', Math.min(App.constants.reembarkation.num_citizens, App.constants.game_creation.num_starting_citizens));

      self.set('srcItems', {});
      self.set('dstItems', {});
      self.set('maxDstItems', App.constants.reembarkation.num_items);

      // Trace citizens.
      self._popTrace = App.population.getTrace();
      self._popTrace.progress(function (pop) {
         var srcCitizens = radiant.map_to_array(pop.citizens, function (k, v) {
            if (k === 'size') {
               return false;  // ignore size field from population data
            }
            if (v.__self) {
               return v.__self;  // get game object id
            }
         });
         var dstCitizens = self.get('dstCitizens');
         radiant.each(dstCitizens, function (k, v) {
            if (srcCitizens.contains(v)) {
               srcCitizens.removeObject(v);  // Already selected for re-embark.
            } else {
               dstCitizens.removeObject(v);  // No longer exists.
            }
         });
         self.set('srcCitizens', srcCitizens);
         self.set('dstCitizens', dstCitizens);
         self.notifyPropertyChange('srcCitizens');
         self.notifyPropertyChange('dstCitizens');
      });

      // Trace items that can be sold and therefore carried over directly.
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:sellable_item_tracker')
         .done(function (response) {
            self._sellableItemsTrace = new StonehearthDataTrace(response.tracker, {})
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  self.set('sellableItemsTrackingData', response.tracking_data);
               });
         });
      // Trace all items so we can find gold and banners.
      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:basic_inventory_tracker')
         .done(function (response) {
            var traceFields = { 'tracking_data': { 'stonehearth:loot:gold': { 'items': { '*': { 'stonehearth:stacks': {} } } } } };
            self._ownedItemsTrace = new StonehearthDataTrace(response.tracker, traceFields)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  self.set('ownedItemsTrackingData', response.tracking_data);
               });
         });
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      this.$().draggable({ handle: '.title' });

      self.$('#confirmButton').click(function () {
         if (!$(this).is('.disabled')) {
            self.confirm();
         }
      });

      self.$('#dismissButton').click(function () {
         self.destroy();
      });

      self.$('#rejectButton').click(function () {
         var bulletin = self.get('model');
         if (!bulletin) {
            return;
         }
         var instance = bulletin.callback_instance;
         var method = bulletin.data['on_reject'];
         if (!method) {
            return;
         }

         radiant.call_obj(instance, method);
      });

      self._srcItemPalette = self.$('.srcItemsList').stonehearthItemPalette({
         click: function (item) {
            self.set('selectedSrcItem', item);
         },
         rightClick: function (item) {
            self.set('selectedSrcItem', item);
            self._transferItem(true);
         },
      });
      self._srcItemPalette.stonehearthItemPalette('showSearchFilter');

      self._dstItemPalette = self.$('.dstItemsList').stonehearthItemPalette({
         click: function (item) {
            self.set('selectedDstItem', item);
         },
         rightClick: function (item) {
            self.set('selectedDstItem', item);
            self._transferItem(false);
         },
      });
   },

   destroy: function () {
      if (this._popTrace) {
         this._popTrace.destroy();
         this._popTrace = null;
      }
      if (this._sellableItemsTrace) {
         this._sellableItemsTrace.destroy();
         this._sellableItemsTrace = null;
      }
      if (this._ownedItemsTrace) {
         this._ownedItemsTrace.destroy();
         this._ownedItemsTrace = null;
      }
      if (this._srcItemPalette) {
         this._srcItemPalette.stonehearthItemPalette('destroy');
         this._srcItemPalette = null;
      }
      if (this._dstItemPalette) {
         this._dstItemPalette.stonehearthItemPalette('destroy');
         this._dstItemPalette = null;
      }
      this._super();
   },

   // ACE: added check for reembark_max_count in item catalog data
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
   }.observes('sellableItemsTrackingData', 'ownedItemsTrackingData'),

   _updatePalettes: function () {
      this._srcItemPalette.stonehearthItemPalette('updateItems', this.get('srcItems'));
      this._dstItemPalette.stonehearthItemPalette('updateItems', this.get('dstItems'));
   }.observes('srcItems', 'dstItems'),

   numDstCitizens: function () {
      return this.get('dstCitizens').length;
   }.property('dstCitizens'),

   numDstItems: function () {
      var sum = 0;
      radiant.each(this.get('dstItems'), function (key, entry) {
         sum += entry.count;
      });
      return sum;
   }.property('dstItems'),

   isConfigValid: function () {
      return this.get('numDstCitizens') > 0;
   }.property('numDstCitizens'),

   canAddItem: function () {
      return this.get('selectedSrcItem') && this.get('numDstItems') < this.get('maxDstItems');
   }.property('numDstItems', 'selectedSrcItem'),

   canAddCitizen: function () {
      return this.get('selectedSrcCitizen') && this.get('numDstCitizens') < this.get('maxDstCitizens');
   }.property('numDstCitizens', 'selectedSrcCitizen'),

   confirm: function () {
      var self = this;
      var bulletin = self.get('model');
      if (!bulletin) {
         return;
      }
      var instance = bulletin.callback_instance;
      var method = bulletin.data['on_confirm'];
      if (!method) {
         return;
      }

      var choices = {
         citizens: this.get('dstCitizens'),
         items: radiant.map_to_array(this.get('dstItems'), function (k, v) {
            return { uri: v.uri, count: v.count, item_quality: parseInt(v.item_quality) };
         })
      };
      radiant.call_obj(instance, method, choices)
         .done(function(r) {
            // On success, save the re-embark record on the client.
            radiant.call('stonehearth:save_reembark_spec_command', r.spec_id, r.spec_record);
         });
   },

   actions: {
      addSelectedCitizen: function () {
         this._transferCitizen(true);
      },
      removeSelectedCitizen: function () {
         this._transferCitizen(false);
      },
      addSelectedItem: function () {
         this._transferItem(true);
      },
      removeSelectedItem: function () {
         this._transferItem(false);
      },
   },

   _transferCitizen: function (isSrc) {
      var self = this;
      var citizenKey = isSrc ? 'selectedSrcCitizen' : 'selectedDstCitizen';
      var citizen = self.get(citizenKey);
      if (!citizen) {
         return;
      }
      if (isSrc && self.get('numDstCitizens') == self.get('maxDstCitizens')) {
         return;  // Too many.
      }

      var from = isSrc ? self.get('srcCitizens') : self.get('dstCitizens');
      var to = isSrc ? self.get('dstCitizens') : self.get('srcCitizens');
      from.removeObject(citizen.__self);
      to.pushObject(citizen.__self);

      self.notifyPropertyChange('dstCitizens');
      self.notifyPropertyChange('srcCitizens');

      self.set(citizenKey, null);
   },

   _transferItem: function (isSrc) {
      var self = this;
      var itemKey = isSrc ? 'selectedSrcItem' : 'selectedDstItem';
      var item = self.get(itemKey);
      if (!item) {
         return;
      }
      if (isSrc && self.get('numDstItems') == self.get('maxDstItems')) {
         return;  // Too many.
      }

      var from = isSrc ? self.get('srcItems') : self.get('dstItems');
      var to = isSrc ? self.get('dstItems') : self.get('srcItems');
      var key = item.attr('uri') + App.constants.item_quality.KEY_SEPARATOR + item.attr('item_quality');

      if (!to[key]) {
         to[key] = radiant.shallow_copy(from[key]);
         to[key].count = 0;
      }
      to[key].count++;

      from[key].count--;
      if (from[key].count == 0) {
         delete from[key];
      }

      self.notifyPropertyChange('dstItems');
      self.notifyPropertyChange('srcItems');

      if (!from[key]) {
         self.set(itemKey, null);
      }
   },
});

// ACE: added functionality for displaying citizens' pets to take along on reembarkation
App.StonehearthReembarkationBulletinRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'stonehearthReembarkationBulletinRow',
   uriProperty: 'model',
   dialogView: null,

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:job': {},
      'stonehearth:attributes': {},
      // ACE: added pets to reembarkation
      'stonehearth:pet_owner': {
         'pets': {
            '*': {
               'stonehearth:unit_info': {},
            },
         },
      },
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self.$().bind('contextmenu', function () {
         self.dialogView.set(self.get('isSrc') ? 'selectedSrcCitizen' : 'selectedDstCitizen', self.get('model'));
         self.dialogView._transferCitizen(self.get('isSrc'));
      });

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
   }.observes('model.stonehearth:pet_owner.pets'),

   isSelected: function () {
      return this.dialogView.get(this.get('isSrc') ? 'selectedSrcCitizen' : 'selectedDstCitizen') == this.get('model');
   }.property('isSrc', 'dialogView.selectedSrcCitizen', 'dialogView.selectedDstCitizen', 'model'),

   actions: {
      selectPerson: function () {
         this.dialogView.set(this.get('isSrc') ? 'selectedSrcCitizen' : 'selectedDstCitizen', this.get('model'));
      }
   }
});
