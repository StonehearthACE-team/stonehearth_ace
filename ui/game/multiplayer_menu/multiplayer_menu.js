App.StonehearthMultiplayerMenuView.reopen({
   _updateParty: function() {
      var self = this;
      var maxPlayers = self.get('maxPlayers');
      var clients = self.get('clientsArray');
      var party = [];
      for (var i = 0; i < maxPlayers; i++) {
         var data = {};
         data.colorStyle = 'background-color: rgba(0,0,0,0); opacity: 0.2;';
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
   }
});
