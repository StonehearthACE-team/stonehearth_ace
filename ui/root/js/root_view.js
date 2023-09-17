App.RootController = Ember.Controller.extend({
   _minAutoSaveInterval: 5,   // minutes
   _maxAutoSaveInterval: 30,   // minutes
   
   init: function() {
      var self = this;
      self._super();

      self._autoSaveInterval = self._minAutoSaveInterval * 60 * 1000

      stonehearth_ace.getModConfigSetting('stonehearth_ace', 'auto_save_interval', function(value) {
            self._setAutoSaveInterval(value);
         });
      $(top).on("auto_save_interval_changed", function (_, e) {
         self._setAutoSaveInterval(e.value);
      });
   },

   _setAutoSaveInterval: function(interval) {
      var self = this;
      self._autoSaveInterval = Math.max(self._minAutoSaveInterval, Math.min(self._maxAutoSaveInterval, parseInt(interval || 0))) * 60 * 1000;
   },

   // have to override this to defer resume
   // _autoSave: function() {
   //    var self = this;
   //    var saveView = App.stonehearthClient.getSaveView();
   //    var enabled = saveView.get('auto_save');
   //    var escMenuView = App.gameView ? App.gameView.getView(App.StonehearthEscMenuView) : null;
   //    var escMenuVisible = escMenuView ? (!escMenuView.isDestroyed && !escMenuView.isDestroying) : false;

   //    if (enabled && !escMenuVisible) {
   //       radiant.call('stonehearth:dm_pause_game')
   //          .done(function(response) {
   //             saveView.send('saveGame', 'auto_save', function() {
   //                radiant.call('stonehearth:dm_resume_game');
   //             });
   //          });
   //    }
   // },

   _autoSave: function() {
      var self = this;
      var saveView = App.stonehearthClient.getSaveView();
      var enabled = saveView.get('auto_save');
      var escMenuView = App.gameView ? App.gameView.getView(App.StonehearthEscMenuView) : null;
      var escMenuVisible = escMenuView ? (!escMenuView.isDestroyed && !escMenuView.isDestroying) : false;

      if (enabled && !escMenuVisible) {
         radiant.call('stonehearth:dm_pause_game')
            .done(function(response) {
               saveView.send('saveGame', 'auto_save');
               radiant.call('stonehearth:dm_resume_game');
            });
      }
   },

   actions: {
      // every X minutes, check if autosave is enabled, and if it is, save.
      // ACE: override this function to use timeouts instead of intervals to easily transition auto save intervals
      tryAutoSave: function(start) {
         var self = this;
          // Get the controller once to initialize it (Sigh)
          // Otherwise we don't get the controller when we first try to save -yshan
         var saveView = App.stonehearthClient.getSaveView();
         if (start) {
            this._timeoutTicket = setTimeout(function autoSaveTimeout() {
                  //only autosave if we're the host
                  if (App.stonehearthClient.isHostPlayer()) {
                     self._autoSave();
                     self._timeoutTicket = setTimeout(autoSaveTimeout, self._autoSaveInterval);
                  }
               }, self._autoSaveInterval);
         } else {
            clearTimeout(this._timeoutTicket);
         }
      },
   },
}),

App.RootView = Ember.ContainerView.extend({

   init: function() {
      this._super();
      var self = this;

      // Make sure any views we create have a hotkey manager to use.
      App.hotkeyManager = new StonehearthHotkeyManager();

      // create the views
      this._debugView = this.createChildView(App["StonehearthDebugView"]);
      this._gameView  = this.createChildView(App["StonehearthGameUiView"]);
      this._shellView = this.createChildView(App["StonehearthShellView"]);

      // push em
      this.pushObject(this._gameView)
      this.pushObject(this._shellView)
      this.pushObject(this._debugView)

      // accessors for easy access throughout the app
      App.gameView = this._gameView;
      App.shellView = this._shellView;
      App.debugView = this._debugView;

      // Routing state
      this._ready = false;
      this._currentRoute = undefined;
      this._currentScreenName = undefined;

      this._game_mode_manager = new GameModeManager();

      App.navigate = function (route, options) {
         console.log('Navigating to: ', route, options);
         return radiant.call_obj('radiant.ui', 'navigate_command', route, options || {});
      }

      App.getGameMode = function() {
         return self._game_mode_manager.getGameMode();
      };

      App.setGameMode = function(...args) {
         self._game_mode_manager.setGameMode(...args);
      };

      App.setVisionMode = function(mode) {
         self._game_mode_manager.setVisionMode(mode);
      };

      App.getVisionMode = function() {
         return self._game_mode_manager.getVisionMode();
      };

      App.getCurrentScreenName = function() {
         return self._currentScreenName !== undefined ? self._currentScreenName : 'shell'; // default to shell, undefined should be overridden when trace comes back
      }

      App.waitForFrames = function(numFrames, callback) {
         var f = function(numFramesLeft, callback) {
            if (numFramesLeft <= 0) {
               callback();
            } else {
               App.waitForFrames(numFrames - 1, callback);
            }
         };

         window.requestAnimationFrame(function(frameTime) {
            f(numFrames, callback);
         });
      };

      App.tooltipHelper = new StonehearthTooltipHelper();
      App.statusHelper = new StonehearthStatusHelper();


      this.screens = {}
      this.screens['shell'] = {
         containerView: this._shellView,
         init: () => {

         },
         show: () => {
            $('#' + this._shellView.elementId).show();
         },
         hide: () => {
            $('#' + this._shellView.elementId).hide();
         }
      }

      this.screens['game'] = {
         containerView: this._gameView,
         init: () => {
            App.waitForGameLoad().then(() => {
               App.stonehearthClient.Setup();
               radiant.call_obj('stonehearth.analytics', 'on_browser_loaded_command'); // tells analytics to grab another snapshot
               radiant.call_obj('stonehearth.game_speed', 'on_game_load_complete_command');
               $(document).trigger('stonehearthGameStarted');

               radiant.call_obj('stonehearth.world_generation', 'place_camp_if_needed_command')
                  .done(function(e) {
                     if (e.result === true) {
                        // If we need camp placement, start the camp placement
                        radiant.call('radiant:get_config', 'mods.stonehearth.tutorial')
                           .done(function(o) {
                              var tutorial_config = o['mods.stonehearth.tutorial'];
                              if (tutorial_config && tutorial_config.hide_camera_tutorial) {
                                 App.gameView.addView(App.StonehearthCreateCampView);
                              } else {
                                 App.gameView.addView(App.StonehearthHelpCameraView);
                              }
                           });
                     } else {
                        App.gameView.addCompleteViews();
                     }
                  });

                  radiant.call_obj('stonehearth.session', 'is_host_player_command')
                     .done(function(e) {
                        if (e.is_host) {
                           radiant.call('radiant:get_config', 'mods.stonehearth.tutorial')
                              .done(function(o) {
                                 var tutorial_config = o['mods.stonehearth.tutorial'];
                                 if ((tutorial_config && !tutorial_config.hide_intro_tutorial) || !tutorial_config) {
                                    App.stonehearthTutorials = new StonehearthTutorialManager();
                                    App.stonehearthTutorials.start();
                                 }
                              });
                        }
                     });
            });
         },
         show: () => {
            $('#' + this._gameView.elementId).show();
            this.get('controller').send('tryAutoSave', true);
         },
         hide: () => {
            $('#' + this._gameView.elementId).hide();
            this.get('controller').send('tryAutoSave', false);
         }
      };

      // ACE: add custom game modes and entity mode checking
      self._game_mode_manager.addCustomMode("military", "military"); //, null, "AceMilitaryModeView", true);
      self._game_mode_manager.addCustomMode("connection", "hud");
      self._game_mode_manager.addCustomMode("farm", "hud", "create_farm");
      self._game_mode_manager.addCustomMode("fence", "hud", null, "AceBuildFenceModeView");
      //self._game_mode_manager.addCustomMode("planter", "normal", null, "AceHerbalistPlanterView");
      self._game_mode_manager.addCustomEntityModeCheck(self._getCustomModeForEntity);

      App.getGameModeManager = function() {
         return self._game_mode_manager;
      };
   },

   didInsertElement: function() {
      var self = this;
      // Hide all screens
      for (var screen in this.screens) {
         $('#' + this.screens[screen].containerView.elementId).hide();
      }

      radiant.call('radiant:get_ui_route_datastore')
         .done(function(o) {
            self._routeTrace = radiant.trace(o.route_datastore)
               .progress(function(routeUpdate) {
                  self.handleRoute(routeUpdate);
               })
               .fail(function(o) {
                   console.log('route trace failed! ', o)
               });
         });
   },

   handleRoute: function(routeUpdate) {
      let newRoute = routeUpdate.route;
      if (!newRoute || newRoute === '') { return; }
      if (newRoute === this._currentRoute) { return; }
      this._currentRoute = newRoute;

      let options = routeUpdate.options || {};
      let parts = newRoute.split('/');
      var screenName = parts[0];
      var screenViewName = parts[1];
      let screen = this.screens[screenName];

      console.log('Routing:', newRoute, options);

      if (screenName !== this._currentScreenName) {
         if (this.screens.hasOwnProperty(screenName)) {

            if (this._currentScreenName) {
               let currentScreen = this.screens[this._currentScreenName];
               currentScreen.hide();
            }

            this._currentScreenName = screenName;

            if (!screen._initialized) {
               screen.init();
               screen._initialized = true;
            }

            screen.show();
         }
      }

      // Our views are all in the same scope, so 'game/StonehearthSelectGameStoryView' will work, but it's invalid.
      screen.containerView.handleRoute(screenViewName, options);

      if (!this._ready) {
         this._ready = true;
         $(document).trigger('stonehearthReady');
      }
   },

   // ACE: additional game modes
   _getCustomModeForEntity: function(modes, entity, curMode, consideredMode) {
      if (entity['stonehearth:farmer_field']) {
         return modes.FARM;
      }

      if (entity['stonehearth_ace:patrol_banner'] || entity['stonehearth:party']) {
         return modes.MILITARY;
      }

      if (entity['stonehearth_ace:connection'] && consideredMode == modes.NORMAL) {
         return modes.CONNECTION;
      }

      if (entity['stonehearth_ace:fish_trap'] || entity['stonehearth_ace:quest_storage_zone']) {
         return modes.ZONES;
      }

      // if (entity['stonehearth_ace:herbalist_planter']) {
      //    return modes.PLANTER;
      // }

      return null;
   },
});
