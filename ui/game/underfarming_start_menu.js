(function() {
	 createUnderfarm = function() {	
		var mc = this;

         App.setGameMode('zones');
         var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.zone_menu.items.create_underfarm.tip_title',
               'stonehearth_ace:ui.game.menu.zone_menu.items.create_underfarm.tip_description', { i18n: true });

         return App.stonehearthClient._callTool('createUnderfarm', function(){
            return radiant.call('stonehearth_ace:choose_new_underfield_location')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               radiant.call('stonehearth:select_entity', response.field);
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
               console.log('new underfield created!');
            });
         });
      };
	  
   $(top).on('stonehearthReady', function () {
      var menuActions = App.StonehearthStartMenuView.proto().menuActions;
      menuActions.create_underfarm = function() {
         createUnderfarm();
      };
   });
})();