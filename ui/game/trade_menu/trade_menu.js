App.StonehearthTradeMenuView = App.View.extend({
   templateName: 'tradeMenu',
   uriProperty: 'model',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,
   components: {
      "target_sellable_items": {
         "tracking_data" : {
            "*" : {}
         }
      },
      "source_sellable_items": {
         "tracking_data" : {
            "*" : {}
         }
      }
   },

   init: function() {
      this._super();
      var self = this;
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self.buildSourceSellable();
      self.buildSourceOffered();

      self.buildTargetSellable();
      self.buildTargetRequested();

      self._updateMaxOfferedGold();
      self._updateMaxRequestedGold();

      self.$('#give1Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._addGifts(1);
         }
      });

      self.$('#give10Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._addGifts(10);
         }
      });

      self.$('#remove1GiftButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._removeGifts(1);
         }
      });

      self.$('#remove10GiftButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._removeGifts(10);
         }
      });

      self.$('#request1Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._addRequests(1);
         }
      });

      self.$('#request10Button').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._addRequests(10);
         }
      });

      self.$('#remove1RequestButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._removeRequests(1);
         }
      });

      self.$('#remove10RequestButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            self._removeRequests(10);
         }
      });

      self.$('#sendTradeButton').click(function() {
         if (!$(this).hasClass('disabled')) {
            var offeredGold = App.stonehearth.validator.enforceNumRange(self.$('#offeredGold'))
            var requestedGold = App.stonehearth.validator.enforceNumRange(self.$('#requestedGold'))

            radiant.call_obj('stonehearth.trade', 'send_trade_command', offeredGold, requestedGold)
               .done(function(o) {
                     App.stonehearthClient.closeTradeMenu();
                  });
         }
      });

      self.$('#cancelTradeButton').click(function() {
         radiant.call_obj('stonehearth.trade', 'cancel_active_trade_command')
            .done(function(o) {
                  App.stonehearthClient.closeTradeMenu();
               });
      });

      self.$('.closeButton').click(function() {
         radiant.call_obj('stonehearth.trade', 'cancel_active_trade_command')
            .done(function(o) {
               });
      });

      self.$('#offeredGold')
         .keydown(function (e) {
               if (e.keyCode == 13 && !e.originalEvent.repeat) {
                  $(this).blur();
               }
            })
         .blur(function (e) {
            self._updateSendButton();
         });

      self.$('#requestedGold')
         .keydown(function (e) {
               if (e.keyCode == 13 && !e.originalEvent.repeat) {
                  $(this).blur();
               }
            })
         .blur(function (e) {
            self._updateSendButton();
         });

      self.$('.numericButton').click(function() {
         Ember.run.scheduleOnce('afterRender', self, '_updateSendButton');
      });
   },

   willDestroyElement: function() {
      this._sourceSellablePalette.stonehearthItemPalette('destroy');
      this._sourceOfferedPalette.stonehearthItemPalette('destroy');
      this._targetSellablePalette.stonehearthItemPalette('destroy');
      this._targetRequestedPalette.stonehearthItemPalette('destroy');

      this.$().find('.tooltipstered').tooltipster('destroy');

      this.$('#give1Button').off('click');
      this.$('#give10Button').off('click');
      this.$('#request1Button').off('click');
      this.$('#request10Button').off('click');
      this.$('#remove1GiftButton').off('click');
      this.$('#remove10GiftButton').off('click');
      this.$('#remove1RequestButton').off('click');
      this.$('#remove10RequestButton').off('click');

      this.$('#sendTradeButton').off('click');
      this.$('#cancelTradeButton').off('click');

      this.$('.closeButton').off('click');

      self.$('#offeredGold').off('keydown').off('blur');
      self.$('#requestedGold').off('keydown').off('blur');

      self.$('.numericButton').off('click');

      this._super();
   },


   _updateTownNames: function() {
      var self = this;

      self.set('sourceTownName', App.presenceClient.getPlayerDisplayName(self.get('model.source_player_id')));

      self.set('targetTownName', App.presenceClient.getPlayerDisplayName(self.get('model.target_player_id')));
   }.observes('model.target_player_id', 'model.source_player_id'),

   _updateMaxOfferedGold: function() {
      var self = this;

      self.$('#offeredGold').attr({"max": self.get('model.source_gold')});
   }.observes('model.source_gold'),

   _updateMaxRequestedGold: function() {
      var self = this;

      self.$('#requestedGold').attr({"max": self.get('model.target_gold')});
   }.observes('model.target_gold'),

   buildSourceSellable: function() {
      var self = this;

      self._sourceSellablePalette = this.$('#sourceSellable').stonehearthItemPalette({
         cssClass: 'shopItem',
         itemAdded: function(itemEl, itemData) {
            itemEl.attr('num', itemData.num);
         },
         click: function(item, e) {
            self._updateGiveButtons();
         },
         rightClick: function (item, e) {
            self._updateGiveButtons();
            self._addGifts(1);
         }
      });

      // ACE: add search filter to source sellable item palette
      self._sourceSellablePalette.stonehearthItemPalette('showSearchFilter');
   },

   buildSourceOffered: function() {
      var self = this;

      self._sourceOfferedPalette = this.$('#sourceOffered').stonehearthItemPalette({
         cssClass: 'shopItem',
         itemAdded: function(itemEl, itemData) {
            itemEl.attr('num', itemData.num);
         },
         click: function(item, e) {
            self._updateRemoveGiftButtons();
         },
         rightClick: function (item, e) {
            self._updateRemoveGiftButtons();
            self._removeGifts(1);
         }
      });
   },

   buildTargetSellable: function() {
      var self = this;

      self._targetSellablePalette = this.$('#targetSellable').stonehearthItemPalette({
         cssClass: 'shopItem darkItem',
         itemAdded: function(itemEl, itemData) {
            itemData.count = null;
         },
         click: function(item, e) {
            self._updateRequestButtons();
         },
         rightClick: function (item, e) {
            self._updateRequestButtons();
            self._addRequests(1);
         }
      });
      
      // ACE: add search filter to target sellable item palette
      self._targetSellablePalette.stonehearthItemPalette('showSearchFilter');
   },

   buildTargetRequested: function() {
      var self = this;

      self._targetRequestedPalette = this.$('#targetRequested').stonehearthItemPalette({
         cssClass: 'shopItem',
         itemAdded: function(itemEl, itemData) {
            itemEl.attr('num', itemData.num);
         },
         click: function(item, e) {
            self._updateRemoveRequestButtons();
         },
         rightClick: function (item, e) {
            self._updateRemoveRequestButtons();
            self._removeRequests(1);
         }
      });
   },

   _getSellableItems(tracking_data) {
      var sellable_items = {}
      radiant.each(tracking_data, function(uri, uri_entry) {
         radiant.each(uri_entry.item_qualities, function(item_quality_key, data) {
            data.uri = uri_entry.uri;
            // The key's purpose is just to make sure each entry with a different item quality is unique
            var key = data.uri + '&item_quality=' + item_quality_key;
            sellable_items[key] = data;
         });
      });
      return sellable_items;
   },

   updateSourceSellable: function() {
      if (!this.$()) {
         return;
      }
      var tracking_data = this.get('model.source_sellable_items.tracking_data');
      var sellable_items = this._getSellableItems(tracking_data);
      this._sourceSellablePalette.stonehearthItemPalette('updateItems', sellable_items);
      this.set('show.source_sellable', !$.isEmptyObject(sellable_items));
      this._updateGiveButtons();
   }.observes('model.source_sellable_items'),

   updateSourceOffered: function() {
      var offeredItems = this.get('model.offered_items');
      var itemList = this._getItemList(offeredItems);

      this._sourceOfferedPalette.stonehearthItemPalette('updateItems', itemList);
      this.set('show.offered', !$.isEmptyObject(itemList));
      this._updateRemoveGiftButtons();
      this._updateSendButton();
   }.observes('model.offered_items'),

   updateTargetSellable: function() {
      if (!this.$()) {
         return;
      }
      var tracking_data = this.get('model.target_sellable_items.tracking_data');
      var sellable_items = this._getSellableItems(tracking_data);
      this._targetSellablePalette.stonehearthItemPalette('updateItems', sellable_items);
      this.set('show.target_sellable', !$.isEmptyObject(sellable_items));
      this._updateRequestButtons();
   }.observes('model.target_sellable_items'),

   updateTargetRequested: function() {
      var requestedItems = this.get('model.requested_items');
      var itemList = this._getItemList(requestedItems);

      this._targetRequestedPalette.stonehearthItemPalette('updateItems', itemList);
      this.set('show.requested', !$.isEmptyObject(itemList));
      this._updateRemoveRequestButtons();
      this._updateSendButton();
   }.observes('model.requested_items'),

   _getItemList: function(itemMap) {
      var self = this;

      var itemList = {};

      radiant.each(itemMap, function(uri, qualityEntries) {
         var catalogData = App.catalog.getCatalogData(uri);
         var uriEntries = radiant.each(qualityEntries, function(quality, entities) {
               var numEntities = typeof entities == "number" ? entities : radiant.map_to_array(entities).length;
               if (numEntities == 0) {
                  return;
               }
               
               var itemData = {
                  uri : uri,
                  item_quality: quality,
                  kind: 'uri',
                  identifier : uri,
                  count : numEntities
               };

               if (catalogData) {
                  itemData.name = catalogData.display_name;
                  itemData.icon = catalogData.icon;
               }
               
               var key = uri + '&item_quality=' + quality;
               itemList[key] = itemData;
            });
      });

      return itemList;
   },

   _addGifts: function(quantity) {
      var self = this;

      var selected = self.$('#sourceSellable .selected');
      var uri = selected.attr('uri');
      if (uri) {
         var quality = parseInt(selected.attr('item_quality'));

         radiant.call_obj('stonehearth.trade', 'add_gifts_command', uri, quality, quantity)
            .done(function(o) {
               });
      }
   },

   _removeGifts: function(quantity) {
      var self = this;

      var selected = self.$('#sourceOffered .selected');
      var uri = selected.attr('uri');
      if (uri) {
         var quality = parseInt(selected.attr('item_quality'));

         radiant.call_obj('stonehearth.trade', 'remove_gifts_command', uri, quality, quantity)
            .done(function(o) {
               });
      }
   },

   _addRequests: function(quantity) {
      var self = this;

      var selected = self.$('#targetSellable .selected');
      var uri = selected.attr('uri');
      if (uri) {
         var quality = parseInt(selected.attr('item_quality'));

         radiant.call_obj('stonehearth.trade', 'add_requests_command', uri, quality, quantity)
            .done(function(o) {
               });
      }
   },

   _removeRequests: function(quantity) {
      var self = this;

      var selected = self.$('#targetRequested .selected');
      var uri = selected.attr('uri');
      if (uri) {
         var quality = parseInt(selected.attr('item_quality'));

         radiant.call_obj('stonehearth.trade', 'remove_requests_command', uri, quality, quantity)
            .done(function(o) {
               });
      }
   },

   _updateGiveButtons: function() {
      var self = this;

      if (self.get('show.source_sellable') && self.$('#sourceSellable .selected').length != 0) {
         self._enableButton('#give1Button');
         self._enableButton('#give10Button');
      } else {
         self._disableButton('#give1Button');
         self._disableButton('#give10Button');
      }
   },

   _updateRemoveGiftButtons: function() {
      var self = this;

      if (self.get('show.offered') && self.$('#sourceOffered .selected').length != 0) {
         self._enableButton('#remove1GiftButton');
         self._enableButton('#remove10GiftButton');
      } else {
         self._disableButton('#remove1GiftButton');
         self._disableButton('#remove10GiftButton');
      }
   },

   _updateRequestButtons: function() {
      var self = this;

      if (self.get('show.target_sellable') && self.$('#targetSellable .selected').length != 0) {
         self._enableButton('#request1Button');
         self._enableButton('#request10Button');
      } else {
         self._disableButton('#request1Button');
         self._disableButton('#request10Button');
      }
   },

   _updateRemoveRequestButtons: function() {
      var self = this;

      if (self.get('show.requested') && self.$('#targetRequested .selected').length != 0) {
         self._enableButton('#remove1RequestButton');
         self._enableButton('#remove10RequestButton');
      } else {
         self._disableButton('#remove1RequestButton');
         self._disableButton('#remove10RequestButton');
      }
   },

   _updateSendButton: function() {
      var self = this;

      var offeredGold = App.stonehearth.validator.enforceNumRange(self.$('#offeredGold'));
      var requestedGold = App.stonehearth.validator.enforceNumRange(self.$('#requestedGold'));

      if (self.get('show.requested') || self.get('show.offered') || offeredGold != 0 || requestedGold != 0) {
         self._enableButton('#sendTradeButton');
      } else {
         self._disableButton('#sendTradeButton');
      }
   },

   _disableButton: function(buttonId, tooltipId) {
      // Disable the button with a tooltip if provided.
      self.$(buttonId).addClass('disabled');
   },

   _enableButton: function(buttonId) {
      self.$(buttonId).removeClass('disabled');
   }

});
