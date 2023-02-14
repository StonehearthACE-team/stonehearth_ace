$(document).ready(function(){
   $(top).on("radiant_place_item", function (_, e) {
      var item = e.entity;

      // don't execute if player doesn't own the item
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'} )
      App.stonehearthClient.placeItem(item);
   });

   $(top).on("radiant_undeploy_item", function (_, e) {
      var item = e.entity;

      // don't execute if player doesn't own the item
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:popup' })
      App.stonehearthClient.undeployItem(item);
   });

   $(top).on("radiant_undeploy_golem", function (_, e) {
      var item = e.entity;

      // don't execute if player doesn't own the item
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      radiant.call('radiant:play_sound', { 'track': 'stonehearth:sounds:ui:start_menu:popup' })
      App.stonehearthClient.undeployGolem(item);
   });
});

App.StonehearthPlaceItemView = App.View.extend({
   templateName: 'stonehearthPlaceItem',
   modal: false,

   init: function() {
      this._super();
      var self = this;

      $(top).on('mode_changed', function(_, mode) {
         self._onStateChanged();
      });
   },

   didInsertElement: function() {
      var self = this;
      self._super();
      self.hide();
   },

   _onStateChanged: function() {
      var self = this;
      if (App.getGameMode() != 'place') {
         self.hide();
      }
   }
});

App.StonehearthPlaceItemPaletteView = App.View.extend({
   templateName: 'stonehearthPlaceItemPalette',
   classNames: ['fullScreen', 'flex', 'gui', 'stonehearth-view'],

   init: function() {
      var self = this;
      $(top).on('stonehearth_place_item', function() {
         if (self.$().is(':visible')) {
            self.hide();
         } else {
            App.setGameMode('place');
            self.show();
         }
      });
   },

   didInsertElement: function() {
      var self = this;
      this._super();
      this.hide();

      if (this._trace) {
         return;
      }

      // build the palette
      this._palette = this.$('#items').stonehearthItemPalette({
         click: function(item) {
            var itemType = item.attr('uri');
            var quality = parseInt(item.attr('item_quality'));
            App.stonehearthClient.placeItemType(itemType, quality);
         }
      });

      // ACE: add search filter to this item palette
      this._palette.stonehearthItemPalette('showSearchFilter');

      return radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:placeable_item_inventory_tracker')
         .done(function (response) {
            var traceFields = {
               "tracking_data": {
                  "*": {
                     "item_qualities": {}
                  }
               }
            };
            self._trace = new StonehearthDataTrace(response.tracker, traceFields)
               .progress(function(response) {
                  self._placeableItems = {}

                  radiant.each(response.tracking_data, function(uri, uri_entry) {
                     radiant.each(uri_entry.item_qualities, function (item_quality_key, item) {
                        item.uri = uri_entry.uri
                        item.iconic_uri = uri_entry.iconic_uri
                        if (item.num_placements_requested) {
                           item.count = item.count - item.num_placements_requested;
                        }
                        if (item.count > 0) {
                           self._placeableItems[uri + App.constants.item_quality.KEY_SEPARATOR + item_quality_key] = item;
                        }
                     });
                  });

                  if (self.get('isVisible')) {
                     self._palette.stonehearthItemPalette('updateItems', self._placeableItems);
                  }
               });
         })
         .fail(function(response) {
            console.error(response);
         })
   },

   _reactToVisibilityChanged: function () {
      var self = this;
      if (self.get('isVisible')) {
         self._palette.stonehearthItemPalette('updateItems', self._placeableItems);
      }
   }.observes('isVisible'),

   willDestroyElement: function() {
      this._palette.stonehearthItemPalette('destroy');
      this._super();
   },

   destroy: function() {
      if (this._trace) {
         this._trace.destroy();
         this._trace = null;
      }
   },

});
