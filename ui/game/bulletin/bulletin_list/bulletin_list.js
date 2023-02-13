App.StonehearthBulletinList = App.View.extend({
	templateName: 'bulletinList',
   closeOnEsc: true,

   init: function() {
      var self = this;
      self._super();
   },

   didInsertElement: function() {
      radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:popup'});
      var self = this;
      self._super();

      this.$().draggable({ handle: '.title' });

      this.$().on('click', '.row', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:page_down'});
         var row = $(this);
         var id = row.attr('id');

         var bulletin = self._getBulletin(id);

         if (bulletin) {
            App.bulletinBoard.zoomToLocation(bulletin);
            if (bulletin.get('type') === 'alert') {
               App.bulletinBoard.markBulletinHandled(bulletin);
            } else {
               App.bulletinBoard.showDialogView(bulletin);
            }
         }
      });

      // ACE: added right click option to dismiss a bulletin directly from the list
      this.$().on('contextmenu', '.row', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:page_down'});
         var row = $(this);
         var id = row.attr('id');

         var bulletin = self._getBulletin(id);

         if (bulletin) {
            App.bulletinBoard.markBulletinHandled(bulletin);
         }
      });
   },

   _getBulletin: function(id) {
      var self = this;
      var bulletins = self.get('context').bulletins;
      var alerts = self.get('context').alerts;

      for (var i = 0; i < bulletins.length; i++) {
         if (bulletins[i].id == id) {
            return bulletins[i];
         }
      }
      for (var i = 0; i < alerts.length; i++) {
         if (alerts[i].id == id) {
            return alerts[i];
         }
      }

      return null;
   },

   willDestroyElement: function() {
      this.$().off('click', '.row');
      this.$().off('contextmenu', '.row');
      this._super();
   }
});
