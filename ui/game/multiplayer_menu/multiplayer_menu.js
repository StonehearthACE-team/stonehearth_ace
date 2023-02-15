App.StonehearthMultiplayerMenuView = App.View.extend({
   templateName: 'stonehearthMultiplayerMenu',
   closeOnEsc: true,
   uriProperty: 'model',
   hideOnCreate: false,

   _clients: {},
   _confirmView: null,
   _settingsView: null,
   _friendsListView: null,

   init: function() {
      this._super();
      var self = this;

      self.set('isHostPlayer', App.stonehearthClient.isHostPlayer());
   },

   destroy: function() {
      if (this._sessionTrace) {
         this._sessionTrace.destroy();
         this._sessionTrace = null;
      }

      App.presenceClient.removeChangeCallback('multiplayer_menu');

      if (this._friendsListView != null && !this._friendsListView.isDestroyed) {
         this._friendsListView.destroy();
         this._friendsListView = null;
      }

      this._super();
   },

   didInsertElement: function() {
      var self = this;
      self._super();

      self.$().draggable({ handle: '.title' });

      self.$('#multiplayerMenu').on('mousedown', function(e) {
         var element = $(e.target);
         // Deselect if we aren't clicking a button
         if (element && !element.is("button")) {
            self.set('selectedRow', null);
            self.$('.row').removeClass('selected');
            self._updateSelectedRow();
         }
      });

      radiant.call('radiant:is_steam_present')
         .done(function (response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            var present = response.present;
            self.set('steamPresent', present);
            self._updateParty();
         });

      radiant.call('stonehearth:get_service', 'session_server')
         .done(function(response) {
            self._sessionServiceUri = response.result;
            self._sessionTrace = new RadiantTrace(self._sessionServiceUri, self.components)
               .progress(function(service) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }

                  self.set('maxPlayers', service.max_players);
                  self.set('remoteConnectionsDisabled', !service.remote_connections_enabled);

                  if (!self._initialized) {
                     self._initializeMenu();
                  }

                  self._updateParty();
               });
            });

      if (self.hideOnCreate) {
         self.hide();
      }
   },

   willDestroyElement: function() {
      if (this._confirmView) {
         this._confirmView.destroy();
         this._confirmView = null;
      }
      if (this._settingsView) {
         this._settingsView.destroy();
         this._settingsView = null;
      }
      this.$().find('.tooltipstered').tooltipster('destroy');
      this.$('#multiplayerMenu').off('mousedown');
      this._super();
   },

   dismiss: function () {
      this.hide();
   },

   hide: function () {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }
      this._super();
   },

   show: function () {
      this._super();
      App.stonehearth.modalStack.push(this);
   },

   actions: {
      disconnectPlayer: function() {
         this._showConfirmView('disconnect_player', function(playerId) {
            radiant.call_obj('stonehearth.player', 'disconnect_player_command', playerId);
         });
      },
      erasePlayer: function() {
         var self = this;
         this._showConfirmView('erase_player', function(playerId) {
            radiant.call_obj('stonehearth.player', 'destroy_player_entities_command', playerId)
               .done( function(o) {
                  self._updateClientArray();
               });;
         });
      },
      transferPlayer: function() {
         var self = this;
         this._showConfirmView('transfer_player', function(playerId) {
            radiant.call_obj('stonehearth.player', 'transfer_player_entities_command', playerId, App.stonehearthClient.getHostPlayerId())
               .done( function(o) {
                  self._updateClientArray();
               });;
         });
      },
      showSettings: function() {
         this._showMultiplayerSettingsView();
      },
      startTradeWithPlayer: function() {
         var self = this;
         var playerId = self.get('selectedRow.playerId');
         if (playerId) {
            radiant.call_obj('stonehearth.trade', 'start_trade_command', playerId)
               .done(function(o) {
                     App.stonehearthClient.showTradeMenu(o.trade);
                  });
         }
      },
      openFriendsList: function() {
         var self = this;
         if (self._friendsListView != null && !self._friendsListView.isDestroyed) {
            self._friendsListView.destroy();
            self._friendsListView = null;
         }
         self._friendsListView = App.gameView.addView(App.StonehearthFriendsListView);
      }
   },

   _initializeMenu: function() {
      var self = this;

      if (self._initialized) {
         return;
      }

      self.$('#multiplayerMenu').show();

      var changeCallback = function(presenceData) {
         if (self.isDestroying || self.isDestroyed) {
            return;
         }

         if (Object.keys(presenceData).length != Object.keys(self._clients).length) {
            self._clients = {};
         }

         var addedNewClient = false;
         radiant.each(presenceData, function(playerId, data) {
            if (self._updateClientData(playerId, data)) {
               addedNewClient = true;
            }
         });

         if (addedNewClient) {
            self._updateClientArray();
         }
      }

      App.presenceClient.addChangeCallback('multiplayer_menu', changeCallback, true);

      self._initialized = true;

      self._updateParty();
   },

   _showMultiplayerSettingsView: function() {
      var self = this;
      if (self._settingsView) {
         self._settingsView.destroy();
      }
      self._settingsView = App.gameView.addView(App.StonehearthMultiplayerSettingsView, {
         title : i18n.t('stonehearth:ui.game.multiplayer_settings.settings'),
         showEnableOption: true,
         buttons : [
            {
               label: i18n.t('stonehearth:ui.game.common.ok'),
               click: function(options) {
                  radiant.call_obj('stonehearth.session_server', 'set_remote_connections_enabled_command', options.remote_connections_enabled);
                  if (options.remote_connections_enabled) {
                     radiant.call_obj('stonehearth.session_server', 'set_max_players_command', options.max_players);
                  }
                  radiant.call_obj('stonehearth.game_speed', 'set_anarchy_enabled_command', options.game_speed_anarchy_enabled);
               }
            },
            {
               label: i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.cancel')
            }
         ]
      });
   },

   _showConfirmView: function(actionName, actionCb) {
      var self = this;
      var playerId = self.get('selectedRow.playerId');
      if (self._confirmView != null && !this._confirmView.isDestroyed) {
         self._confirmView.destroy();
         self._confirmView = null;
      }

      self._confirmView = App.gameView.addView(App.StonehearthConfirmView, {
         title : i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.' + actionName + '.title'),
         message : i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.' + actionName + '.message'),
         buttons : [
            {
               label: i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.continue'),
               click: function() {
                  actionCb(playerId);
                  self._clearClientData(playerId);
                  self.set('selectedRow', null);
               }
            },
            {
               id: 'confirmRemove',
               label: i18n.t('stonehearth:ui.game.multiplayer_menu.confirm.cancel')
            }
         ]
      });
   },

   _updateSelectedRow: function(view) {
      var view = this.get('selectedRow');
      if (view) {
         var selectingDifferentPlayer = view.playerId != App.stonehearthClient.getPlayerId();
         this.set('selectingOtherPlayer', selectingDifferentPlayer);
         var isHostPlayer = App.stonehearthClient.isHostPlayer();
         var canShowButtons = isHostPlayer && selectingDifferentPlayer;
         this.set('showPlayerManagementButtons', canShowButtons);
      } else {
         this.set('showPlayerManagementButtons', false);
         this.set('selectingOtherPlayer', false);
      }
   }.observes('selectedRow'),

   _updateClientData: function(playerId, connectionData) {
      var self = this;
      var isInitialized = self._clients[playerId] != null;
      var addedNewClient = false;
      if (!isInitialized) {
         var clientData = {
            playerId: playerId,
            connectionData: connectionData,
         };

         self._clients[playerId] = clientData;
         addedNewClient = true;
      } else {
         self._clients[playerId].connectionData = connectionData;
         self.set('updatedClientData', self._clients[playerId]);
      }

      var numConnected = 0;
      radiant.each(self._clients, function(playerId, clientData) {
         if (clientData && radiant.isOnline(clientData.connectionData)) {
            numConnected++;
         }
      });

      self.set('numConnected', numConnected);
      return addedNewClient;
   },

   _clearClientData: function(playerId) {
      delete this._clients[playerId];
   },

   _updateClientArray: function() {
      var self = this;
      var clients = radiant.map_to_array(self._clients);
      App.presenceClient.sortClientsArray(clients);

      self.set('clientsArray', clients);
      Ember.run.scheduleOnce('afterRender', this, function() {
         self._updateSelectedRow();
      });

      self._updateParty();
   },

   _updateParty: function() {
      var self = this;
      var maxPlayers = self.get('maxPlayers');
      var clients = self.get('clientsArray');
      var party = [];
      for (var i = 0; i < maxPlayers; i++) {
         var data = {};
         data.colorStyle = 'background-color: rgba(0,0,0,0); opacity: 0.2;';
         // ACE: added null check for clients
         if (clients && i < clients.length) {
            var color = clients[i].connectionData.player_color;
            if (color) {
               if (radiant.isOnline(clients[i].connectionData)) {
                  data.colorStyle = 'background-color: rgba(' + color.x + ',' + color.y + ',' + color.z + ', 1)';
               } else {
                  data.colorStyle = 'background-color: rgba(' + color.x + ',' + color.y + ',' + color.z + ', 0.5)';
               }
            }
         }
         party.push(data);
      }
      self.set('partyArray', party);

      if ((clients && clients.length >= maxPlayers) || !self.get('steamPresent')) {
         self.set('shouldHideInvite', true);
      } else {
         self.set('shouldHideInvite', false);
      }
   },

   _updateTooltips: function() {
      Ember.run.scheduleOnce('afterRender', function() {
         if (!(self.$('#remoteConnectionsDisabled').hasClass('tooltipstered'))) {
            self.$('#remoteConnectionsDisabled').tooltipster();
         }
      });
   }.observes('remoteConnectionsDisabled'),
});


App.StonehearthFriendsListView = App.View.extend({
   templateName: 'stonehearthFriendsList',
   closeOnEsc: true,
   uriProperty: 'model',

   _playerStates: {
      OFFLINE : 0,
      ONLINE : 1,
      BUSY : 2,
      AWAY : 3,
      SNOOZE : 4
   },

   didInsertElement: function() {
      var self = this;
      radiant.call('radiant:get_friends_list')
         .done(function(o) {
            var friendsList = radiant.map_to_array(o, function(k, v) {
               v.steamId = k;
               v.status = i18n.t('stonehearth:ui.game.multiplayer_menu.offline');
               v.offline = v.state == self._playerStates.OFFLINE; // we gray everything out if a player is completely offline
               v.order = 1000;

               if (v.state == self._playerStates.ONLINE) {
                  v.status = i18n.t('stonehearth:ui.game.multiplayer_menu.online');
                  v.order = 0;
               } else if (v.state == self._playerStates.BUSY) {
                  v.status = i18n.t('stonehearth:ui.game.multiplayer_menu.busy');
                  v.order = 1;
               } else if (v.state == self._playerStates.AWAY || v.state == self._playerStates.SNOOZE) {
                  v.status = i18n.t('stonehearth:ui.game.multiplayer_menu.away');
                  v.order = 2;
               } else if (v.state > self._playerStates.SNOOZE) {
                  v.status = i18n.t('stonehearth:ui.game.multiplayer_menu.online');
                  v.order = 2;
               }

               v.steamAvatar = '/r/steam_avatar/' + k;

               return v;
            });

            friendsList.sort(function(a,b) {
               if (a.order != b.order) {
                  return a.order - b.order;
               }
               return a.name < b.name ? -1 : 1;
            });

            self.set('friendsList', friendsList);
         });
   },

   actions: {
      inviteFriend: function(steamId) {
         var self = this;
         radiant.call('radiant:invite_friend_to_game', steamId)
            .done(function(o) {
               if (!self.isDestroyed) {
                  self.destroy();
               }
            });
      }
   }
});
