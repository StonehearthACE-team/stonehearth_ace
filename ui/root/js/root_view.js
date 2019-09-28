// other modders can also reopen this, override init, and add their own custom modes and entity mode checks
App.RootView.reopen({
   init: function() {
      this._super();
      var self = this;

      // also apply any stonehearthClient changes we want to make here
      self._applyStonehearthClientChanges();

      self._game_mode_manager.addCustomMode("military", "military"); //, null, "AceMilitaryModeView", true);
      self._game_mode_manager.addCustomMode("connection", "hud");
      self._game_mode_manager.addCustomMode("farm", "hud", "create_farm");
      self._game_mode_manager.addCustomMode("fence", "hud", null, "AceBuildFenceModeView");
      self._game_mode_manager.addCustomEntityModeCheck(self._ACE_getCustomModeForEntity);
   },

   _ACE_getCustomModeForEntity: function(modes, entity) {
      if (entity['stonehearth:farmer_field']) {
         return modes.FARM;
      }

      if (entity['stonehearth_ace:patrol_banner'] || entity['stonehearth:party']) {
         return modes.MILITARY;
      }

      if (entity['stonehearth_ace:connection']) {
         return modes.CONNECTION;
      }

      return null;
   },

   _applyStonehearthClientChanges: function() {
      App.stonehearthClient._placeItemOrItemType = function (placementType, toolName, item, quality) {
         var self = this;
         var placementCall = placementType == 'item' ? 'stonehearth:choose_place_item_location' : 'stonehearth:choose_place_item_type_location';

         radiant.call('stonehearth:check_can_place_item', item, quality)
            .done(function (response) {
               radiant.call('stonehearth_ace:get_custom_tooltip_command', item, 'stonehearth:ui.game.menu.build_menu.items.place_item')
               .done(function (r) {
                  var custom_tooltips = r.custom_tooltips;
                  var tip_title = custom_tooltips.tip_title || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_title';
                  var tip_description = custom_tooltips.tip_description || 'stonehearth:ui.game.menu.build_menu.items.place_item.tip_description';
                  var tip_bindings = custom_tooltips.tip_bindings || {left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'};
                  self.showTipWithKeyBindings(tip_title, tip_description, tip_bindings);

                  App.setGameMode('place');
                  return self._callTool(toolName, function() {
                     return radiant.call(placementCall, item, quality)
                        .done(function(response) {
                           radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} )
                           if ((placementType == 'itemType') && response.more_items) {
                              self.placeItemType(item, quality);
                           } else {
                              self.hideTip();
                           }
                        })
                        .fail(function(response) {
                           //App.setGameMode('normal');
                           self.hideTip();
                        })
                        .always(function(response) {
                           if (placementType == 'item') {
                              App.setGameMode('normal');
                              self.hideTip();
                           }
                        });
                  });
               });
            })
            .fail(function(response) {
               self.showTip(i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_title'),
                            i18n.t('stonehearth:ui.game.menu.build_menu.items.cannot_place_item.tip_description', {
                               tag: i18n.t("i18n(stonehearth:ui.game.unit_frame.placement_tags." + response.placement_tag + ")"),
                               num: response.num_placed || 0,
                               max: response.max_placeable || 0
                            }),
                            {warning: 'warning'});
            });
      };

      App.stonehearthClient.deactivateAllTools = function() {
         var self = this;
         return radiant.call('stonehearth:deactivate_all_tools')
            .always(function() {
               if (self._activeTool && (self._activeTool.state() == "resolved" || self._activeTool.state() == "rejected")) {
                  self._activeTool.state() = null;
               }
            });
      };
     
      App.stonehearthClient.showPromotionTree = function(entity_id, job_index) {
         var view = App.stonehearth.promotionTreeView;
         if (view && view.get('citizen.__self') == entity_id) {
            view.dismiss();
         } else if (view) {
            view.show(entity_id, job_index);
         } else {
            App.stonehearth.promotionTreeView = App.gameView.addView(App.StonehearthPromotionTree, {
               citizen: entity_id,
               job_index: job_index
            });
         }
      };

      App.stonehearthClient.showCharacterSheet = function(entity) {
         if (this._petCharacterSheet != null && !this._petCharacterSheet.isDestroyed) {
            this._petCharacterSheet.destroy();
            this._petCharacterSheet = null;
         }
         if (this._characterSheet != null && !this._characterSheet.isDestroyed) {
            if (this._characterSheet.get('uri') == entity) {
               this._characterSheet.dismiss();
            }
            else {
               this._characterSheet.set('uri', entity);
               this._characterSheet.show();
            }
         } else {
            this._characterSheet = App.gameView.addView(App.StonehearthCitizenCharacterSheetView, { uri: entity });
         }
      };

      App.stonehearthClient.showPetCharacterSheet = function(entity) {
         if (this._characterSheet != null && !this._characterSheet.isDestroyed) {
            this._characterSheet.dismiss();
         }

         if (this._petCharacterSheet != null && !this._petCharacterSheet.isDestroyed) {
            this._petCharacterSheet.set('uri', entity);
         } else {
            this._petCharacterSheet = App.gameView.addView(App.StonehearthPetCharacterSheetView, { uri: entity });
         }
      };

      App.stonehearthClient.showBuildFenceView = function() {
         var view = App.stonehearth.buildFenceView;
         if (view) {
            view.show();
         }
         else {
            App.stonehearth.buildFenceView = App.gameView.addView(App.AceBuildFenceModeView);
         }
      };

      App.stonehearthClient.createFarm = function(fieldType) {
         var self = this;

         App.setGameMode('zones');
         var tip = self.showTipWithKeyBindings('stonehearth:ui.game.menu.zone_menu.items.create_farm.tip_title',
               'stonehearth_ace:ui.game.menu.zone_menu.items.create_farm.tip_description',
               {left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'});

         return this._callTool('createFarm', function(){
            return radiant.call('stonehearth:choose_new_field_location', fieldType)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               radiant.call('stonehearth:select_entity', response.field);
               self.createFarm(fieldType);
            })
            .fail(function(response) {
               self.hideTip(tip);
               console.log('new field created!');
            });
         });
      };
   }
});