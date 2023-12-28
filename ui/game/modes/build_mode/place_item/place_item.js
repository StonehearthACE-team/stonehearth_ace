var lastPlaceItemTabPage = 'placeItemTab';
var placeItemTypeGameMode = 'place_item';

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
   classNames: ['fullScreen', 'flex', 'gui', 'stonehearth-view'],
   modal: false,

   init: function() {
      this._super();
      var self = this;

      $(top).on('mode_changed', function(_, mode) {
         self._onStateChanged();
      });

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

      this.tabs = this.$('.tab');
      this.tabs.click(function() {
         lastPlaceItemTabPage = $(this).attr('tabPage');
      });

      self._createPlaceItemPalette();
      self._createCraftAndPlaceItemPalette();

      // Resume on last selected tab
      self._resumeLastTab();
   },

   _createPlaceItemPalette: function() {
      var self = this;

      // build the palette
      this._palette = this.$('#placeItems').stonehearthItemPalette({
         click: function(item) {
            var itemType = item.attr('uri');
            var quality = parseInt(item.attr('item_quality'));
            App.stonehearthClient.placeItemType(itemType, quality, placeItemTypeGameMode);
         }
      });

      // ACE: add search filter to this item palette
      this._palette.stonehearthItemPalette('showSearchFilter');

      radiant.call_obj('stonehearth.inventory', 'get_item_tracker_command', 'stonehearth:placeable_item_inventory_tracker')
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
         });
   },

   _createCraftAndPlaceItemPalette: function() {
      var self = this;
      
      // build the palette
      this._craftPalette = this.$('#craftAndPlaceItems').stonehearthItemPalette({
         hideCount: true,
         showZeroes: true,
         click: function(item) {
            var itemType = item.attr('uri');
            App.stonehearthClient.craftAndPlaceItemType(itemType, placeItemTypeGameMode);
         }
      });

      // ACE: add search filter to this item palette
      this._craftPalette.stonehearthItemPalette('showSearchFilter');

      //  When someone's job or level changes, let us know.
      App.jobController.addChangeCallback('craft_and_place_items', function() {
         self._updateCraftableItems();
      }, true);
   },

   _updateCraftableItems: function() {
      var self = this;
      var craftableItems = {};

      var jobData = App.jobController.getJobControllerData();
      if (!jobData || !jobData.jobs) {
         return;
      }

      _.forEach(jobData.jobs, function(jobControllerInfo, jobUri) {
         if (!jobControllerInfo.recipe_list) {
            return;
         }

         if (jobControllerInfo.num_members <= 0) {
            // do not show if nobody has been promoted to this crafter
            return;
         }

         var jobInfo = App.jobConstants[jobUri];
         var jobIcon, jobName;
         if (jobInfo) {
            jobIcon = jobInfo.description.icon;
            jobName = jobInfo.description.display_name;
         }

         var highestLevel = jobControllerInfo.highest_level;

         _.forEach(jobControllerInfo.recipe_list, function(category) {
            _.forEach(category.recipes, function(recipe_info, recipe_key) {
               var recipe = recipe_info.recipe;
               var level = Math.max(1, recipe.level_requirement || 1);
               if (level > highestLevel) {
                  // do not show if no one can craft it
                  return;
               }

               if (recipe.manual_unlock && !jobControllerInfo.manually_unlocked[recipe.recipe_key]) {
                  // do not show if no one can craft it
                  return;
               }

               var product_uri = recipe.product_uri;
               var key = product_uri + App.constants.item_quality.KEY_SEPARATOR + '1';
               if (!craftableItems[key]) {
                  var catalogData = App.catalog.getCatalogData(product_uri);
                  if (!catalogData || !catalogData.is_placeable) {
                     // No data for the product or product is not a placeable item
                     return;
                  }

                  // TODO: include crafter info (job name, icon, and level)
                  // and insert into tooltips somehow? also searching
                  var entry = {
                     uri: product_uri,
                     category: catalogData.category,
                     description: catalogData.description,
                     display_name: catalogData.display_name,
                     appeal: catalogData.appeal,
                     icon: catalogData.icon,
                     craftedBy: {
                        jobUri: jobUri,
                        jobName: jobName,
                        jobIcon: jobIcon,
                        jobLevel: level,
                     },
                  };

                  craftableItems[key] = entry;
               }
            });
         });
      });

      self._craftableItems = craftableItems

      if (self.get('isVisible')) {
         self._craftPalette.stonehearthItemPalette('updateItems', self._craftableItems);
      }
   },

   _reactToVisibilityChanged: function () {
      var self = this;
      if (self.get('isVisible')) {
         self._palette.stonehearthItemPalette('updateItems', self._placeableItems);
         self._craftPalette.stonehearthItemPalette('updateItems', self._craftableItems);
      }
   }.observes('isVisible'),

   willDestroyElement: function() {
      this.tabs.off('click');
      this._palette.stonehearthItemPalette('destroy');
      this._craftPalette.stonehearthItemPalette('destroy');
      this.$().find('.tooltipstered').tooltipster('destroy');
      this._super();
   },

   destroy: function() {
      if (this._trace) {
         this._trace.destroy();
         this._trace = null;
      }
   },

   _onStateChanged: function() {
      var self = this;
      if (App.getGameMode() != 'place') {
         self.hide();
      }
   },

   _resumeLastTab: function() {
      this.$('div[tabPage]').removeClass('active');
      this.$('.tabPage').hide();

      var tab = this.$('div[tabPage=' + lastPlaceItemTabPage + ']');
      tab.addClass('active');

      var tabPage = this.$('#' + lastPlaceItemTabPage);
      tabPage.show();
   },

});
