App.StonehearthBulletinList.reopen({
   didInsertElement: function() {
      var self = this;
      self._super();

      self.$().on('contextmenu', '.row', function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:page_down'});
         var row = $(this);
         var id = row.attr('id');

         var bulletin = self._getBulletin(id);

         if (bulletin) {
            App.bulletinBoard.markBulletinHandled(bulletin);
         }
      });
   },

   willDestroyElement: function() {
      var self = this;
      self.$().off('contextmenu', '.row');
      self._super();
   }
})