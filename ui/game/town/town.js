App.StonehearthTownView.reopen({
   lastClickedUri: null,
   lastClickedItem: null,

   init: function() {
      var self = this;
      self._super();

      radiant.call('stonehearth:get_town')
         .done(function (response) {
            self._townTrace = new StonehearthDataTrace(response.result, { 'town_bonuses': { '*': {} }, 'default_storage': { '*': {}} })
               .progress(function (response) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }
                  self._townDataChanged(response);
               });
         });
   },

   _townDataChanged: function(data) {
      var self = this;
      var bonuses = [];
      radiant.each(data.town_bonuses, (uri, bonus) => {
         bonuses.push({ display_name: bonus.display_name, description: bonus.description });
      });
      self.set('townBonuses', bonuses);

      self._defaultStorage = data.default_storage;
      self._updateDefaultStorage();
   },

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

                  radiant.call('stonehearth_ace:get_item_container', self.lastClickedItem)
                     .done(function(response) {
                        if (self.isDestroyed || self.isDestroying) {
                           return;
                        }
                        var camera_focus = self.lastClickedItem;
                        if (response.container && response.container != '') {
                           // if it's a universal_storage, the response will also contain access_nodes; just use the first one that's in the world
                           if (response.access_nodes) {
                              for (var i = 0; i < response.access_nodes.length; i++) {
                                 var access_node = response.access_nodes[i];
                                 if (access_node.in_world) {
                                    camera_focus = access_node.entity;
                                    break;
                                 }
                              }
                           }
                           else {
                              camera_focus = response.container;
                           }
                        }
                        // select and focus on the item, but if the item is in a container, focus on the container
                        radiant.call('stonehearth:select_entity', self.lastClickedItem);
                        radiant.call('stonehearth:camera_look_at_entity', camera_focus);
                     });
               }
         }
      });
      self._inventoryPalette.stonehearthItemPalette('showSearchFilter');

      App.tooltipHelper.attachTooltipster(self.$('#defaultStorageLabel'),
         $(App.tooltipHelper.createTooltip(null, i18n.t('stonehearth_ace:ui.game.zones_mode.stockpile.default_storage.tooltip')))
      );
   },

   _updateDefaultStorage: $.throttle(250, function () {
      var self = this;
      if (!self.$()) return;

      var items = [];
      radiant.each(self._defaultStorage, function (id, storage) {
         var catalogData = App.catalog.getCatalogData(storage.uri);
         if (catalogData) {
            var item = {
               id: id,
               entityId: storage.__self,
               icon: catalogData.icon
            };
            items.push(item);
         }
      });

      self.set('defaultStorage', items);
      self.set('hasDefaultStorage', items.length > 0);

      Ember.run.scheduleOnce('afterRender', this, function() {
         var elements = self.$('.defaultStorageItem');
         if (elements) {
            elements.each(function() {
               var $el = $(this);
               var entity = self._getDefaultStorageEntity($el.attr('storage-id'));
               var catalogData = App.catalog.getCatalogData(entity.uri);
               App.tooltipHelper.createDynamicTooltip($el, function () {
                  return $(App.tooltipHelper.createTooltip(i18n.t(catalogData.display_name), i18n.t(catalogData.description)));
               });
            });
         }
      });
   }),

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
   },

   _getDefaultStorageEntity: function(id) {
      return this._defaultStorage && this._defaultStorage[id];
   },

   actions: {
      goToDefaultStorage: function(id) {
         var entity = this._getDefaultStorageEntity(id);
         var entityId = entity && entity.__self;
         if (entityId) {
            radiant.call('stonehearth:select_entity', entityId);
            radiant.call('stonehearth:camera_look_at_entity', entityId);
         }
      }
   }
});