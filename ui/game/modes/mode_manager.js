var GameModeManager;

/*
$(document).ready(function() {
   // when clicking on a tool, don't change modes
   $(document).on( 'click', '.tool', function() {

   }
});
*/

(function () {
   GameModeManager = SimpleClass.extend({

      modes: {
         NORMAL : "normal",
         ZONES : "zones",
         BUILD : "build",
         MINING : "mining",
         PLACEMENT : "place"
      },

      hudModes: {},

      modeMenus: {},

      customEntityModeChecks: [],

      views: {},

      selectionUpdates: {},

      _currentMode: null,
      _currentView: null,
      _currentVisionMode: 'normal',

      _trace_components: {
         "stonehearth:storage": {}
      },

      init: function() {
         var self = this;

         self._selectedEntityTraceDone = false;

         self.hudModes[self.modes.ZONES] = "hud";
         self.hudModes[self.modes.MINING] = "hud";
         self.hudModes[self.modes.PLACEMENT] = "hud";
         self.hudModes[self.modes.BUILD] = "build";

         App.waitForGameLoad().then(() => {
            self.views[self.modes.ZONES] = App.StonehearthZonesModeView.create();
            self.views[self.modes.BUILD] = App.StonehearthBuildModeView.create();
            self.views[self.modes.PLACEMENT] = App.StonehearthPlaceItemView.create();

            App.gameView.addView(self.views[self.modes.ZONES]);
            App.gameView.addView(self.views[self.modes.BUILD]);
            App.gameView.addView(self.views[self.modes.PLACEMENT]);
         });

         $(top).on("start_menu_activated", function(_, e) {
            self._onMenuActivated(e)
         });

         $(top).on("radiant_selection_changed.mode_manager", function (_, e) {
            self._onEntitySelected(e);

            radiant.each(self.selectionUpdates, function(mode, update) {
               if (update) {
                  self.views[mode]._onEntitySelected(e);
               }
            })
         });
      },

      // modders can add their own modes with this function by reopening the root_view.js file (as demonstrated in ACE)
      addCustomMode: function(mode, hudMode, menu, view, sendSelectionUpdates) {
         var self = this;
         var mode_uc = mode.toUpperCase();

         if (self.modes[mode_uc]) return;

         self.modes[mode_uc] = mode;

         if (hudMode) self.hudModes[mode] = hudMode;
         if (menu) self.modeMenus[mode] = menu;

         if (view) {
            App.waitForGameLoad().then(() => {
               var newView = App[view].create();

               if (newView) {
                  newView.hide();
                  self.views[mode] = newView;
                  App.gameView.addView(newView);

                  if (sendSelectionUpdates && newView._onEntitySelected) {
                     self.selectionUpdates[mode] = true;
                  }
               }
            });
         }
      },

      addCustomEntityModeCheck: function(check_fn) {
         this.customEntityModeChecks.push(check_fn);
      },

      setVisionMode: function(mode) {
         this._currentVisionMode = mode;
         radiant.call('stonehearth:set_building_vision_mode', this._currentVisionMode);
         $(document).trigger('stonehearthVisionModeChange', mode);
      },

      getVisionMode: function() {
         return this._currentVisionMode;
      },

      getGameMode: function() {
         return this._currentMode;
      },

      getView: function(mode) {
         return this.views[mode];
      },

      setGameMode: function (mode) {
         if (mode != this._currentMode) {
            App.stonehearthClient.deactivateAllTools();

            // hide the old mode view
            if (this._currentView) {
               this._currentView.hide();
            }

            // show the new mode view, if there is one
            var view = this.views[mode]
            if (view) {
               view.show();
            }

            this._currentView = view;
            this._currentMode = mode;

            // notify the rest of the ui
            $(top).trigger('mode_changed', mode);

            var hudMode = this.hudModes[mode] || 'normal';

            if (hudMode != this._hudMode) {
               radiant.call('stonehearth:set_ui_mode', hudMode);
               this._hudMode = hudMode;
            }
         }
         else if (this._currentView) {
            this._currentView.show();
         }
         else if (mode == 'normal') {
            App.stonehearthClient.deactivateAllTools();
         }
      },

      // if the selected menu is tagged with a game mode, switch to that mode
      _onMenuActivated: function(e) {
         if (!e.nodeData) {
            this.setGameMode(this.modes.NORMAL);
            return;
         }

         // if there's a mode associated with this menu, transition to that mode
         if (e.nodeData["game_mode"]) {
            this.setGameMode(e.nodeData["game_mode"]);
         }
      },

      // swich to the appropriate mode for the selected entity
      _onEntitySelected: function(e) {
         var self = this;
         var entity = e.selected_entity

         if (self.selectedEntityTrace) {
            self.selectedEntityTrace.destroy();
            self.selectedEntityTrace = null;
         }

         if (!entity) {
            //this.setGameMode(this.modes.NORMAL);

            return;
         }

         self._selectedEntityTraceDone = false;
         self.selectedEntityTrace = new RadiantTrace(entity, self._trace_components)
            .progress(function(result) {
               if (this._selectedEntityTraceDone) {
                  return;
               }
               this._selectedEntityTraceDone = true;
               if (App.gameMenu) {
                  var mode = self._getModeForEntity(result);
                  var menu = self._getMenuForMode(mode);
                  if (menu) {
                     self.setGameMode(mode);
                     App.gameMenu.showMenu(menu);
                  } else {
                     var prevMode = self._currentMode;
                     self.setGameMode(mode);
                     // TODO: this is a hack; it shouldn't be a hack
                     // instead of hardcoding in some menus that should get hidden when the gamemode is set to normal,
                     // that should be happening naturally through menu configuration
                     if (prevMode != self.modes.NORMAL) {
                        var currentMenu = App.gameMenu.getMenu();
                        if (currentMenu == self._getMenuForMode(prevMode)) {
                           App.gameMenu.hideMenu();
                        }
                     }
                  }
               }
            })
            .fail(function(e) {
               console.log(e);
            });
      },

      _getMenuForMode: function(gameMode) {
         if (gameMode == this.modes.ZONES) {
            return "zone_menu";
         }

         if (gameMode == this.modes.BUILD) {
            return "custom_building_new";
         }

         return this.modeMenus[gameMode];
      },

      _getModeForEntity: function(entity) {
         var custom_mode = this._getCustomModeForEntity(entity);
         if (custom_mode) {
            return custom_mode;
         }
         
         if ((!entity['stonehearth:ai'] && entity['stonehearth:storage'] && !entity['stonehearth:storage'].is_hidden) ||
               entity['stonehearth:trapping_grounds'] ||
               entity['stonehearth:shepherd_pasture'] ||
               entity['stonehearth:mining_zone'] ||
               entity['stonehearth:defense_zone']) {
            return this.modes.ZONES;
         }
   
         if (entity['stonehearth:fabricator'] ||
               entity['stonehearth:construction_data'] ||
               entity['stonehearth:construction_progress']) {
            return this.modes.BUILD;
         }
   
         return this.modes.NORMAL;
      },
   
      _getCustomModeForEntity: function(entity) {
         var self = this;
         for (var i = 0; i < self.customEntityModeChecks.length; i++)
         {
            var mode = self.customEntityModeChecks[i](self.modes, entity);
            if (mode) {
               return mode;
            }
         }
         
         return null;
      }
   });
})();
