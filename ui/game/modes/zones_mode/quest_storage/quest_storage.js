var updateQuestStorageView = function(data) {
   if (!App.gameView) {
      return;
   }
   let questStorageView = App.gameView.getView(App.StonehearthAceQuestStorageZoneView);
   if (questStorageView && !data.selected_entity) {
      questStorageView.destroy();
   }
};

$(document).ready(function(){
   $(top).on("radiant_selection_changed.quest_storage_zone", function (_, data) {
      updateQuestStorageView(data);
   });
});

App.StonehearthAceQuestStorageZoneView = App.StonehearthBaseZonesModeView.extend({
   templateName: 'aceQuestStorageZone',
   closeOnEsc: true,

   components: {
      "unit_info": {},
      "stonehearth_ace:quest_storage_zone" : {}
   },

   didInsertElement: function() {
      this._super();
      var self = this;

      self.$('button.ok').click(function() {
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:submenu_select'} );
         self.destroy();
      });

      self.$('button.warn').click(function() {
         radiant.call('stonehearth:destroy_entity', self.uri)
         self.destroy();
      });
   },

   showButtons: function() {
      var player_id = App.stonehearthClient.getPlayerId();
      //allow for no player id for things like berry bushes and wild plants that are not owned
      return !this.get('model.player_id') || this.get('model.player_id') == player_id;
   }.property('model.uri'),

   willDestroyElement: function() {
      self.$('button.ok').off('click');
      self.$('button.warn').off('click');
      this._super();
   }
});
