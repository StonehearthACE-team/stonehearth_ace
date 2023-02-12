App.StonehearthTitleScreenView = App.View.extend(Ember.TargetActionSupport, {
   templateName: 'stonehearthTitleScreen',
   i18nNamespace: 'stonehearth',
   components: {},

   _multiplayerSettings: null,
   _confirmView: null,

   init: function() {
      var self = this;
      this._super();

      // Preload splash.
      self._splashImage = new Image();
      self._splashLoaded = $.Deferred();
      self._splashImage.onload = function () { self._splashLoaded.resolve(); };
      self._splashImage.src = '/stonehearth/ui/shell/title/images/foreground.png';
   },

   didInsertElement: function() {
      var self = this;

      // load the about info
      radiant.call('radiant:client_about_info')
         .done(function(o) {
            self.set('productName', o.product_name + ' ' + o.product_version_string + ' (' + o.product_branch + ' ' +  o.product_build_number + ') ' + o.architecture + ' build');
            self._populateAboutDetails(o);
            // self._isOnSteamUnstable = (o.steam_branch === 'latest' || o.steam_branch === 'radiant_stage');
            // self._ReleaseNotesURL = `https://www.stonehearth.net/${o.product_branch}-notes-${o.product_build_number}`;

            // $('#about').click(function(e) {
            //    if (self._isOnSteamUnstable) {
            //       radiant.call('radiant:open_url_external', self._ReleaseNotesURL);
            //    } else {
            //       self.$('#blog').toggle();
            //    }
            // });
         });

      $.get('/stonehearth/release_notes/release_notes.html')
         .done(function(result) {
            self.set('releaseNotes', result);
         })

      // show the load game button if there are saves
      radiant.call("radiant:client:get_save_games")
         .done(function(json) {
            var vals = [];

            $.each(json, function(k ,v) {
               if(k != "__self" && json.hasOwnProperty(k)) {
                  v['key'] = k;
                  vals.push(v);
               }
            });

            // sort by creation time
            vals.sort(function(a, b){
               var tsA = a.gameinfo.timestamp ? a.gameinfo.timestamp : 0;
               var tsB = b.gameinfo.timestamp ? b.gameinfo.timestamp : 0;
               // sort most recent games first
               return tsB - tsA;
            });

            if (vals.length > 0) {
               var save = vals[0];
               var version = save.gameinfo.save_version;
               if (!version) {
                  version = 0;
               }
               if (version < App.minSupportedSaveVersion || version > App.currentSaveVersion) {
                  save.gameinfo.differentVersions = true;
                  $('#continueGameButton').tooltipster();
               }

               var gameDate = save.gameinfo.game_date;
               if (gameDate) {
                  var dateObj = new Date(0, 0, 0, gameDate.hour, gameDate.minute);
                  var localizedTime = dateObj.toLocaleTimeString(i18n.lng(), {hour: '2-digit', minute:'2-digit'});
                  gameDate.time = localizedTime;
               }

               self.$('#continue').show();
               self.$('#continueGameButton').show();
               self.$('#loadGameButton').show();

               self.set('lastSave', save);

               /*
               var ss = vals[0].screenshot;
               $('#titlescreen').css({
                     background: 'url(' + ss + ')'
                  });
               */
            }
            self._loadInProgressUiConfig();
         });

      $('#radiant').fadeIn(800);
      let startTimeMs = Date.now();

      radiant.call_obj('stonehearth.session', 'get_disconnect_reason_command')
         .done(function(response) {
            if (response.reason && response.reason != '') {
               self._addDisconnectPopup(response.reason);
            }
         });

      App.waitForGameLoad().then(() => {
         self._splashLoaded.then(() => {
            let deltaTimeMs = Date.now() - startTimeMs;
            let delay = Math.max(3000 - deltaTimeMs, 0);

            // input handlers
            $(document).keyup(function(e) {
               $('#titlescreen').show();
            });

            $(document).click(function(e) {
               $('#titlescreen').show();
               self._showModConflictScreen();
               self._showACEScreenAndButton();
            });

            setTimeout(function() {
               $('#titlescreen').fadeIn(800, function() {
                  self._showModConflictScreen();
                  self._showACEScreenAndButton();
               });
            }, delay);

            App.stonehearthClient.showSettings(true);
            App.stonehearthClient.showSaveMenu(true);

            // Currently unused: self._startSplashSlideshow();
         });

         // ACE: added version info display
         radiant.call('stonehearth_ace:get_version_info')
            .done(function(response) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }

               var branchClass = response.branch.toLocaleLowerCase() == 'unstable' ? 'aceUnstableBranch' : 'acePre-ReleaseBranch';
               self.set('aceBranchClass', branchClass);
               self.set('aceVersionInfo', response);
               self.set('aceVersion', i18n.t('stonehearth_ace:ui.shell.title_screen.ace_version', response));
            });
      });
   },

   destroy: function() {
      this._super();
      var self = this;
      if (self._multiplayerSettings) {
         self._multiplayerSettings.destroy();
         self._multiplayerSettings = null;
      }
      if (self._confirmView) {
         self._confirmView.destroy();
         self._confirmView = null;
      }
      if (self._slideshowInterval) {
         clearInterval(self._slideshowInterval);
         self._slideshowInterval = null;
      }
   },

   _addDisconnectPopup: function(reason) {
      var self = this;
      if (self._confirmView != null && !this._confirmView.isDestroyed) {
         self._confirmView.destroy();
         self._confirmView = null;
      }

      self._confirmView = App.shellView.addView(App.StonehearthConfirmView, {
         title : i18n.t('stonehearth:ui.game.disconnected.disconnected'),
         message : i18n.t('stonehearth:ui.game.disconnected.reasons.' + reason),
         buttons : [
            {
               label: i18n.t('stonehearth:ui.game.common.ok'),
               click: function() {
                  radiant.call_obj('stonehearth.session', 'clear_disconnect_reason_command');
               }
            }
         ]
      });
   },

   _loadInProgressUiConfig: function() {
      radiant.call('radiant:get_config', 'show_in_progress_ui')
         .done(function(response) {
            if (response.show_in_progress_ui) {
               self.$('#quickStartButton').show();
            } else {
               var lastVisibleButton;

               if (self.$('#loadGameButton').css('display') != 'none') {
                  lastVisibleButton = self.$('#loadGameButton');
               } else {
                  lastVisibleButton = self.$('#newGameButton');
               }

               lastVisibleButton.addClass('last');
            }
         });
   },

   _showModConflictScreen: function() {   
      var self = this; 
      if (self._modConflictScreenShown) {   
         return; 
      } 
  
      self._modConflictScreenShown = true;  
      radiant.call('radiant:client_about_info')   
         .done(function(o) { 
            // Check for mod conflicts
            if (o.mod_conflicts && o.mod_conflicts.length > 0) { 
               var message = i18n.t('stonehearth:ui.shell.title_screen.mod_conflic_dialog.message'); 
               for (var i=0; i < o.mod_conflicts.length; ++i) {  
                  message = message + '<br><font color=\'#ffc000\'><strong>' + o.mod_conflicts[i] + '</strong></font>';  
               }

               App.shellView.addView(App.StonehearthConfirmView, 
                  { 
                     title : i18n.t('stonehearth:ui.shell.title_screen.mod_conflic_dialog.title'),   
                     message : message,  
                     buttons : [   
                        { 
                           label: i18n.t('stonehearth:ui.shell.title_screen.mod_conflic_dialog.accept') 
                        } 
                     ] 
                  });  
            }

            // Check for circular mod dependencies
            if (o.mod_dependency_conflicts && Object.keys(o.mod_dependency_conflicts).length > 0) {
               var message = i18n.t('stonehearth:ui.shell.title_screen.mod_dependency_conflict.message') + '<br>';
               var dependsOnMsg = i18n.t('stonehearth:ui.shell.title_screen.mod_dependency_conflict.dependency');

               radiant.each(o.mod_dependency_conflicts, function(modName, dependencies) {
                  message = message + '<font color=\'#ffc000\'><strong>' + modName + '</strong></font>' + dependsOnMsg;
                  for (var i=0; i < dependencies.length; ++i) {  
                     message = message + '<pre>' + dependencies[i] + '</pre>';
                  }
                  message = message + '<br>';
               });

               App.shellView.addView(App.StonehearthConfirmView, 
                  { 
                     title : i18n.t('stonehearth:ui.shell.title_screen.mod_dependency_conflict.title'),   
                     message : message,  
                     buttons : [   
                        { 
                           label: i18n.t('stonehearth:ui.game.common.ok') 
                        } 
                     ] 
                  });
            }
         });  
   },

   _showACEScreenAndButton: function() {
      var self = this;
      if (self._aceScreenShown) {
         return;
      }

      self._aceScreenShown = true;
      radiant.call('radiant:ace_available')
         .done(function(response) {
            // show the dialog if we haven't before
            if (response.ace_available) {
               if (!response.ace_dialog_shown) {
                  self._acceptedAce = null;
                  App.shellView.addView(App.StonehearthConfirmView,
                     {
                        title : i18n.t('stonehearth:ui.shell.title_screen.ace_dialog.title'),
                        message : i18n.t('stonehearth:ui.shell.title_screen.ace_dialog.message'),
                        buttons : [
                           {
                              label: i18n.t('stonehearth:ui.shell.title_screen.ace_dialog.accept'),
                              click: function () {
                                 self._acceptedAce = true;
                                 radiant.call('radiant:set_config', 'mods.steam_workshop.stonehearth_ace.enabled', true);
                                 radiant.call('radiant:set_config', 'ace_dialog_shown', true);
                              }
                           },
                           {
                              label: i18n.t('stonehearth:ui.shell.title_screen.ace_dialog.cancel'),
                              click: function() {
                                 self._acceptedAce = false;
                                 radiant.call('radiant:set_config', 'mods.steam_workshop.stonehearth_ace.enabled', false);
                                 radiant.call('radiant:set_config', 'ace_dialog_shown', true);
                              }
                           }
                        ],
                        onDestroy: function() {
                           var wasDismissed = self._acceptedAce == null;
                           var enableAceButton = wasDismissed ? response.ace_mod_enabled : self._acceptedAce;
                           // Reload the modules if our selection to enable/disable ACE doesn't match ACE's current load status.
                           // Otherwise if we dismissed the dialog or the status of ACE stays the same, just set up the button w/ the current status
                           if (!wasDismissed && self._acceptedAce != response.ace_mod_enabled) {
                              radiant.call('radiant:client:return_to_main_menu');
                           } else {
                              self._setupACEButton(enableAceButton);
                           }
                        }
                     });
               } else {
                  // set the button up
                  self._setupACEButton(response.ace_mod_enabled);
               }
            }
      });
   },

   _setupACEButton: function(enabled) {
      var self = this;
      var aceButton = self.$('#aceButton');
      if (!aceButton) return;

      self._aceCurrentlyActive = enabled;
      var tooltip = '';

      self.$('#modsButton').addClass('aceActive');
      aceButton.attr('style', '');

      if (self._aceCurrentlyActive) {
         tooltip = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.disable.tooltip');
         aceButton.find('#aceCheck').addClass('checked');
         self.$('#titlescreen').addClass('ace_enabled');
      } else {
         tooltip = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.enable.tooltip');
      }

      aceButton.find('.ace').text(i18n.t('stonehearth:ui.shell.title_screen.ace'));
      aceButton.tooltipster({content: tooltip});
   },

   _startSplashSlideshow: function () {
      var self = this;
      if (self._slideshowInterval) {
         return;
      }

      var SPLASHES = _.shuffle([
         '/stonehearth/ui/shell/title/images/foreground_1.jpg',
         '/stonehearth/ui/shell/title/images/foreground_2.jpg',
         '/stonehearth/ui/shell/title/images/foreground_3.jpg',
         '/stonehearth/ui/shell/title/images/foreground_4.jpg',
      ]);

      // Preload.
      SPLASHES.forEach(function(splash) {
         var image = new Image();
         image.src = splash;
      });

      // Switcher function.
      var curSplashIndex = 0;
      var switchToNextSplash = function () {
         $('#lastSplash').css({
            'background-image': $('#currentSplash').css('background-image')
         });
         $('#currentSplash').css({
            'background-image': 'url(' + SPLASHES[curSplashIndex] + ')',
            'opacity': 0
         });
         $('#currentSplash').animate({ opacity: 1 }, 1000);
         curSplashIndex = (curSplashIndex + 1) % SPLASHES.length;
      };

      // Start it.
      switchToNextSplash();
      self._slideshowInterval = setInterval(switchToNextSplash, 8000);
   },

   actions: {
      newGame: function(multiplayerOptions) {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'} );
         App.navigate('shell/select_game_story', { multiplayerOptions: multiplayerOptions });

         // Clean up these views since we will later instantiate the game view version
         var settingsView = App.shellView.getView(App.SettingsView);
         if (settingsView) {
            settingsView.destroy();
         }

         var saveView = App.shellView.getView(App.SaveView);
         if (saveView) {
            saveView.destroy();
         }
      },

      continueGame: function() {
         //XXX, need to handle validation in an ember-friendly way. No jquery
         if (this.$('#continueGameButton').hasClass('disabled')) {
            return;
         }

         var key = String(this.get('lastSave').key);

         // throw up a loading screen. when the game is loaded the browser is refreshed,
         // so we don't need to worry about removing the loading screen, ever.
         App.stonehearthClient.showModsMatchModal(key);
         // At this point, we just wait to be killed by the client.
      },

      loadGame: function() {
         this.triggerAction({
            action:'openModal',
            actionContext: ['save',
               {
                  allowSaves: false,
               }
            ]
         });
      },

      openMultiplayerSettings: function() {
         var self = this;
         if (self._multiplayerSettings) {
            self._multiplayerSettings.destroy();
         }
         self._multiplayerSettings = App.shellView.addView(App.StonehearthMultiplayerSettingsView, {
            dimBackground: true,
            title: i18n.t('stonehearth:ui.game.multiplayer_settings.create_new_multiplayer_game'),
            buttons : [
               {
                  label: i18n.t('stonehearth:ui.game.multiplayer_settings.start'),
                  click: function(options) {
                     self.send('newGame', options);
                  }
               },
               {
                  label: i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.cancel'),
               }
            ]
         });
      },

      toggleAce: function() {
         var self = this;
         var title = '';
         var message = '';

         if (self._aceCurrentlyActive) {
            title = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.disable.title');
            message = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.disable.message');
         } else {
            title = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.enable.title');
            message = i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.enable.message');
         }

         App.shellView.addView(App.StonehearthConfirmView,
            {
               title : title,
               message : message,
               buttons : [
                  {
                     label: i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.accept'),
                     click: function () {
                        radiant.call('radiant:set_config', 'mods.steam_workshop.stonehearth_ace.enabled', !self._aceCurrentlyActive);
                        radiant.call('radiant:client:return_to_main_menu');
                     }
                  },
                  {
                     label: i18n.t('stonehearth:ui.shell.title_screen.ace_toggle.cancel')
                  }
               ]
            });
      },

      openMods: function() {
         App.navigate('shell/mods');
      },

      // xxx, holy cow refactor this together with the usual flow
      quickStart: function() {
         var self = this;
         var MAX_INT32 = 2147483647;
         var seed = Math.floor(Math.random() * (MAX_INT32+1));

         var width = 12;
         var height = 8;
         this.$().hide();

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:embark'} );
         App.shellView.addView(App.StonehearthLoadingScreenView);

         radiant.call('radiant:get_config', 'mods.stonehearth.world_generation.default_biome')
            .done(function(e) {
               var biome = e['mods.stonehearth.world_generation.default_biome'];
               if (!biome) {
                  biome = 'stonehearth:biome:temperate';
               }
               var options = {
                  game_mode : 'stonehearth:game_mode:normal',
                  biome_src : biome
               };

               radiant.call_obj('stonehearth.game_creation', 'new_game_command', width, height, seed, options)
                  .done(function(e) {
                     var map = e.map;

                     var x, y;
                     // XXX, in the future this will make a server call to
                     // get a recommended start location, perhaps with
                     // a difficulty selector
                     do {
                        x = Math.floor(Math.random() * map[0].length);
                        y = Math.floor(Math.random() * map.length);
                     } while (map[y][x].terrain_code.indexOf('plains') != 0);

                     radiant.call_obj('stonehearth.game_creation', 'generate_start_location_command', x, y, e.map_info);
                     radiant.call('stonehearth:get_world_generation_progress')
                        .done(function(o) {
                           self.trace = radiant.trace(o.tracker)
                              .progress(function(result) {
                                 if (result.progress == 100) {
                                    //TODO, put down the camp standard.

                                    self.trace.destroy();
                                    self.trace = null;

                                    self.destroy();
                                 }
                              })
                        });
                  })
                  .fail(function(e) {
                     console.error('new_game failed:', e)
                  });
            });
      },

      exit: function() {
         radiant.call_obj('stonehearth.analytics', 'game_exit_command')
            .always(function(e) {
               radiant.call('radiant:exit');
            });
      },

      showSaveMenu: function(hideSaveButtons) {
         App.stonehearthClient.showSaveMenu(false, hideSaveButtons);
      },

      settings: function() {
         App.stonehearthClient.showSettings();
      }
   },

   _populateAboutDetails: function(o) {
      var window = $('#aboutDetails');

      window.html('<table>');

      for (var property in o) {
         if (o.hasOwnProperty(property)) {
            window.append('<tr><td>' + property + '<td>' + o[property])
         }
      }

      window.append('</table>');
   }
});
