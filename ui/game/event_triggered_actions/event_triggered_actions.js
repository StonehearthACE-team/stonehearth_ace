$(document).ready(function(){
   $(top).on("stonehearth_ace_place_fish_trap", function (_, e) {
      // don't execute if this isn't the player's hearthling
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      buildFishTrap();
   });

   var buildFishTrap = function() {
      var tip = App.stonehearthClient.showTipWithKeyBindings('stonehearth_ace:data.commands.place_fish_trap.tip_title',
                                                             'stonehearth_ace:data.commands.place_fish_trap.tip_description',
                                                             { left_binding: 'build:rotate:left', right_binding: 'build:rotate:right'});

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

   $(top).on("stonehearth_ace_place_water_pipe", function (_, e) {
      // don't execute if this isn't the player's water pump
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      buildWaterPipe(e.entity);
   });

   var buildWaterPipe = function(fromEntity) {
      var tip = App.stonehearthClient.showTipWithKeyBindings('stonehearth_ace:data.commands.place_water_pipe.tip_title',
                                                             'stonehearth_ace:data.commands.place_water_pipe.tip_description',
                                                             { left_binding: 'build:rotate:left', right_binding: 'build:rotate:right',
                                                               shorter_binding: 'build:sink_template', longer_binding: 'build:raise_template'});

      App.setGameMode('place');
      return App.stonehearthClient._callTool('buildWaterPipe', function() {
         return radiant.call('stonehearth_ace:select_water_pump_pipe_command', fromEntity)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               App.stonehearthClient.hideTip(tip);
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   }

   $(top).on("stonehearth_ace_adjust_gearbox_axles", function (_, e) {
      // don't execute if this isn't the player's gearbox
      if (e.player_id && App.stonehearthClient.getPlayerId() != e.player_id) {
         return;
      }

      adjustGearboxAxles(e.entity);
   });

   var adjustGearboxAxles = function(fromEntity) {
      var tip = App.stonehearthClient.showTipWithKeyBindings('stonehearth_ace:data.commands.adjust_gearbox_axles.tip_title',
                                                             'stonehearth_ace:data.commands.adjust_gearbox_axles.tip_description',
                                                             { left_binding: 'build:rotate:left', right_binding: 'build:rotate:right',
                                                               shorter_binding: 'build:sink_template', longer_binding: 'build:raise_template'});

      App.setGameMode('place');
      return App.stonehearthClient._callTool('adjustGearboxAxles', function() {
         return radiant.call('stonehearth_ace:select_gearbox_axles_command', fromEntity)
            .done(function(response) {
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:place_structure'} );
               App.stonehearthClient.hideTip(tip);
            })
            .fail(function(response) {
               App.stonehearthClient.hideTip(tip);
            });
      });
   }
});