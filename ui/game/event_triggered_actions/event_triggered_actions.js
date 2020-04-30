$(document).ready(function(){
   $(top).on("stonehearth_ace_place_fish_trap", function (_, e) {
      // don't execute if this isn't the player's hearthling
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      buildFishTrap();
   });

   var buildFishTrap = function() {
      var tip = App.stonehearthClient.showTip('stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_title', 'stonehearth_ace:ui.game.menu.build_menu.items.build_well.tip_description',
         {i18n: true});

      App.setGameMode('place');
      return App.stonehearthClient._callTool('buildFishTrap', function() {
         return radiant.call('stonehearth_ace:place_buildable_entity', 'stonehearth_ace:trapper:fish_trap_anchor_ghost')
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               buildFishTrap();
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   }
});