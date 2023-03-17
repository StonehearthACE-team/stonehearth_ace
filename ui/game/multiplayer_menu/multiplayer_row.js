App.StonehearthMultiplayerRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'stonehearthMultiplayerRow',
   uriProperty: 'model',

   components: {},

   clientData: {},
   menuView: null,
   playerId: null,

   didInsertElement: function() {
      var self = this;
      var clientData = self.clientData;
      self._updateConnectionData();
      self.$().on('click', function() {
         // ACE: don't jump to banner when just selecting the row; only do that when clicking the banner/player icon
         // var banner = self.get('townBanner');
         // if (banner) {
         //    radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
         //    radiant.call('stonehearth:camera_look_at_entity', banner)
         //    radiant.call('stonehearth:select_entity', banner);
         // }
         self._selectRow();
      });

      self._traceTown();
   },

   willDestroyElement: function() {
      this.$().off('click');

      if (this._townTrace) {
         this._townTrace.destroy();
         this._townTrace = null;
      }

      this._super();
   },

   isHostPlayer: function() {
      return !!this.get('isHost');
   },

   _traceTown: function() {
      var self = this;

      radiant.call_obj('stonehearth.town', 'get_town_entity_command', self.playerId)
         .done(function(response) {
            var town = response.town;
            if (self._townTrace) {
               return;
            }

            self._townTrace = new StonehearthDataTrace(town, { banner: {} })
               .progress(function(result) {
                  if (self.isDestroyed || self.isDestroying) {
                     return;
                  }

                  // Set town banner icon and entity
                  var townBanner = self.get('townBanner');
                  if (!townBanner || townBanner != result.banner) {
                     if (result.banner) {
                        self.set('townBanner', result.banner.__self);
                        var alias = result.banner.uri;
                        if (alias && alias != '') {
                           var catalogData = App.catalog.getCatalogData(alias);
                           if (catalogData) {
                              self.set('playerIcon', catalogData.icon);
                           }
                        }
                     }
                  }
               })
               .fail(function(e) {
                  console.log(e);
               });

         });
   },

   _updateConnectionData: function() {
      var self = this;

      if (self.isDestroyed || self.isDestroying) {
         return;
      }

      var connectionData = self.clientData.connectionData;
      var steamId = connectionData.steam_id;
      if (steamId) {
         var steamName = App.presenceClient.getSteamName(self.playerId);
         if (steamName && steamName != '') {
            self.set('steamName', steamName);
         }
         radiant.call('radiant:can_see_steam_avatar', steamId)
            .done(function() {
               if (self.isDestroying || self.isDestroyed) {
                  return;
               }
               self.set('steamAvatar', '/r/steam_avatar/' + steamId);
            })
            .fail(function(e) {
               console.log(e);
            });
      }

      var color = connectionData.player_color;
      if (color) {
         self.set('colorStyle', 'background: rgba(' + color.x + ',' + color.y + ',' + color.z + ', 1)');
      }

      var townName = App.presenceClient.getPlayerDisplayName(self.playerId);
      if (townName) {
         self.set('townName', townName);
      }

      var connectionStatus;
      if (radiant.isOnline(connectionData)) {
         self.$().removeClass('inactive');
         if (connectionData.connection_state == App.constants.multiplayer.connection_state.CONNECTING) {
            connectionStatus = i18n.t('stonehearth:ui.game.multiplayer_menu.connecting');
         } else if (!connectionData.is_camp_placed) {
            connectionStatus = i18n.t('stonehearth:ui.game.multiplayer_menu.embarking');
         } else {
            connectionStatus = i18n.t('stonehearth:ui.game.multiplayer_menu.online');
         }
         self.set('is_online', true);
      } else {
         connectionStatus = i18n.t('stonehearth:ui.game.multiplayer_menu.offline');
         self.set('is_online', false);
         self.$().addClass('inactive');
      }

      self.set('connectionStatus', connectionStatus);
      self.set('is_camp_placed', connectionData.is_camp_placed);

      var isHostPlayer = App.stonehearthClient.getHostPlayerId() == self.playerId;
      self.set('isHost', isHostPlayer);

      if (self.menuView._updateParty) {
         self.menuView._updateParty();
      }
   },

   _selectRow: function() {
      var self = this;
      var selected = self.$().hasClass('selected');
      if (!selected) {
         self.menuView.$('.row').removeClass('selected');
         self.$().addClass('selected');

         self.menuView.set('selectedRow', self);
      }
   },

   _clientDataChanged: function() {
      var self = this;
      var clientData = self.menuView.get('updatedClientData');
      if (clientData && clientData.playerId == self.playerId) {
         self.set('clientData', clientData);
         self._updateConnectionData();
      }

   }.observes('menuView.updatedClientData')
});

App.StonehearthPlayerPickerRowView = App.StonehearthMultiplayerRowView.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'stonehearthPlayerPickerRow',
   uriProperty: 'model',

   components: {
   },

   didInsertElement: function() {
      var self = this;
      var clientData = self.clientData;
      self._updateConnectionData();

      self.$('.banner').on('click', function() {
         var banner = self.get('townBanner');
         if (banner) {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
            radiant.call('stonehearth:camera_look_at_entity', banner)
            radiant.call('stonehearth:select_entity', banner);
         }
      });

      if (self.playerId == self.menuView.selectedPlayerId) {
         self.set('isSelected', true);
      }

      self._traceTown();
   },

   willDestroyElement: function() {
      this.$('.banner').off('click');

      this._super();
   },

   actions: {
      selectPlayer: function() {
         this._selectRow();
      }
   },
});
