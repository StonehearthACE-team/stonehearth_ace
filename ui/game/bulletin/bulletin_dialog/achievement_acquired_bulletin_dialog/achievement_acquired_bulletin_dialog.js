App.StonehearthAceAchievementAcquiredBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'achievementAcquiredBulletinDialog',

   didInsertElement: function() {
      this._super();

      this._wireButtonToCallback('.closeButton', '_nop');
   },

   actions: {
      showCharSheet: function() {
         var entity = this.get('model.data.zoom_to_entity')

         if (entity) {
            App.stonehearthClient.showCharacterSheet(entity);
         }
      }
   }
});
