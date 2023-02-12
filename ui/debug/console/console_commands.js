$(document).ready(function(){
   var selected;

   $(top).on("radiant_selection_changed.unit_frame", function (_, data) {
      selected = data.selected_entity;
   });

   // wire up a generic handler to call any registered route.
   radiant.console.register('help', {
      call : function(cmdobj, fn, args) {
         var commands = radiant.console.getCommandHelp();
         var commands = "<p>Available commands:</p>" + commands;
         cmdobj.setContent(commands);
         return;
      },
      description : "Prints out all the registered console commands."
   });

   // wire up a generic handler to call any registered route.
   radiant.console.register('call', {
      call : function(cmdobj, fn, args) {
         var cmd = args._[0];
         var cmdargs = args._.slice(1);
         return radiant.callv(cmd, cmdargs).deferred
      },
      description : "A generic handler to call any registered route."
   });

   radiant.console.register('show_pathfinder_time', {
      graphValueKey: 'total',
      call: function() {
         return radiant.call('radiant:show_pathfinder_time');
      },
   });

   radiant.console.register('destroy', {
      call: function(cmdobjs, fn, args) {
         var entity;
         if (args._.length > 0) {
            entity = 'object://game/' + args._[0];
         } else {
            entity = selected;
         }
         return radiant.call('stonehearth:kill_entity', entity);
      },
      description : "Destroy an entity. Arg 0 is id of the entity. If no argument is provided, destroys the currently selected entity. Usage: destroy 12345",
      test: function(entity) {
         if (entity) {
            return true;
         }
         return false;
      }
   });

   // Usage: select 12345  # enity id
   radiant.console.register('select', {
      call: function(cmdobj, fn, args) {
         var entity = 'object://game/' + args._[0]
         return radiant.call('stonehearth:select_entity', entity);
      },
      description : "Selects the entity with id = Arg 0. Usage: select 12345"
   });

   // Usage: get_config foo.bar.baz
   radiant.console.register('get_config', {
      call: function(cmdobj, fn, args) {
         var key = args._[0]
         return radiant.call('radiant:get_config', key);
      },
      description : "Gets the configuration value from user_settings.config. Usage: get_config foo.bar.baz"
   });

   // Usage: set_config foo.bar.baz { value = 1 }
   radiant.console.register('set_config', {
      call: function(cmdobj, fn, args) {
         var key = args._[0];
         var value = JSON.parse(args._[1]);
         return radiant.call('radiant:set_config', key, value);
      },
      description : "Sets the specified configuration value. Usage: set_config foo.bar.baz {value = 1}"
   });

   radiant.console.register('ib', {
      call: function(cmdobj, fn, args) {
         var thing = args._[0] || selected;

         if (thing) {
            return radiant.call_obj('stonehearth.build', 'instabuild_command', thing);
         } else {
            return radiant.call_obj('stonehearth.building', 'instabuild_command')
         }
      },
      description : "Instantly builds the selected building, or arg 0. Usage: ib object://game/12345",
      test: function(entity) {
         if (entity.get('stonehearth:building') && entity.get('stonehearth:construction_progress')) {
            return true;
         }
         if (entity.get('stonehearth:ladder')) {
            return true;
         }
         return false;
      },
      debugMenuNameOverride: "Insta Build"
   });

   radiant.console.register('im', {
      call: function(cmdobj, fn, args) {
         var mine = args._[0] || selected;
         return radiant.call_obj('stonehearth.mining', 'insta_mine_zone_command', mine);
      },
      description : "Instantly mines the selected mining zone or arg 0. Usage: im object://game/12345",
      test: function(entity) {
         if (entity.get('stonehearth:mining_zone')) {
            return true;
         }
         return false;
      },
      debugMenuNameOverride: "Insta Mine"
   });

   radiant.console.register('get_cost', {
      call: function(cmdobj, fn, args) {
         var building = args._[0] || selected;
         return App.stonehearthClient.getCost(building);
      },
      description : "Get the cost of the selected building, or arg 0. Usage: get_cost object://game/12345"
   });

   radiant.console.register('query_pf', {
      call: function(cmdobj, fn, args) {
         return radiant.call_obj('stonehearth.selection', 'query_pathfinder_command');
      },
      description : "Runs the query pathfinder command. No arguments."
   });

   radiant.console.register('collect_cpu_profile', {
      call: function(cmdobj, fn, args) {
         var profileLength = parseInt(args._[0] || "30000", 10);
         return App.stonehearthClient.collectCpuProfile(profileLength);
      },
      description : "Collects a profile of the LUA code for the specified duration, in ms.  Default is 30s.  Usage: collect_cpu_profile 150000"
   });

   radiant.console.register('toggle_profile_long_ticks', {
      call: function(cmdobj, fn, args) {
         return App.stonehearthClient.profileLongTicks();
      },
      description : "Enables/disables per-game-tick profiling of the LUA code (recorded whenever lua evaluation takes more than a game tick.)"
   });

   radiant.console.register('set_time', {
      call: function(cmdobj, fn, args) {
         var timeStr = args._[0];
         if (!timeStr) {
            cmdobj.setContent("Time not formatted correctly. Usage: set_time 1:25PM");
            return;
         }
         var time = timeStr.match(/(\d+)(?::(\d\d))?\s*(p?)/i);
         if (!time) {
            cmdobj.setContent("Time not formatted correctly. Usage: set_time 1:25PM");
            return;
         }
         var hours = parseInt(time[1], 10);
         if (hours == 12 && !time[3]) {
           hours = 0;
         }
         else {
           hours += (hours < 12 && time[3]) ? 12 : 0;
         }
         var minutes = parseInt(time[2], 10) || 0;

         var timeJSON = {
            "hour" : hours,
            "minute" : minutes
         };

         return App.stonehearthClient.setTime(timeJSON);
      },
      description : "Sets the game time to the time passed in. Usage: set_time 1:25PM"
   });

   radiant.console.register('world_seed', {
      call: function(cmdobj, fn, args) {
         return radiant.call_obj('stonehearth.world_generation', 'get_world_seed_command');
      },
      description : "Returns the world seed of the current world. Usage: world_seed"
   });

   radiant.console.register('reset', {
      call: function(cmdobj, fn, args) {
         var entity;
         if (args._.length > 0) {
            entity = 'object://game/' + args._[0];
         } else {
            entity = selected;
         }

         if (entity) {
            return radiant.call('stonehearth:reset_entity', entity);
         }
         return false;
      },
      description: "Resets the entity's location to a proper one on the ground. Usage: reset",
      test: function(entity) {
         if (entity.get('mob')) {
            return true;
         }
         return false;
      }
   });

   radiant.console.register('get_game_mode', {
      call: function(cmdobj, fn, args) {
         return radiant.call_obj('stonehearth.game_creation', 'get_game_mode');
      },
      description: "Displays the game mode of the current game. Usually either peaceful or normal",
   });

   radiant.console.register('set_blink', {
      call: function(cmdobj, fn, args) {
         return radiant.call_obj('stonehearth.physics', 'set_blink', args._[0] == 'true');
      },
      description: "Make your hearthlings move a little bit faster....",
   });

   radiant.console.register('teleport', {
      call: function(cmdobjs, fn, args) {
         var entity;
         if (args._.length > 0) {
            entity = 'object://game/' + args._[0];
         } else {
            entity = selected;
         }
         if (!entity) {
            return "No entity specified";
         }
         return radiant.call('stonehearth:teleport_entity', entity);
      },
      description : "Teleports the selected entity, or the passed in entity id. Will bring up a UI to select a location Usage: teleport 12345",
      test: function(entity) {
         if (entity && entity.get('mob')) {
            return true;
         }
         return false;
      }
   });

   radiant.console.register('spawn_effect', {
      call: function(cmdobj, fn, args) {
         var entity = selected;
         if (!entity) {
            return "No entity specified";
         }
         var effect_path = args._[0];
         var loop = args._[1] == 'true';
         var delay = args._[2] || 0;
         return radiant.call('stonehearth:spawn_effect', entity, effect_path, loop, delay);
      },
      description : "Spawns an effect on the selected entity, with the option to loop the effect indefinitely.  Can add a delay between spawn loops (in ms).  Usage: spawn_effect /stonehearth/data/effects/level_up true 1000",
      test: function(entity) {
         if (entity && entity.get('mob')) {
            return true;
         }
         return false;
      }
   });

   radiant.console.register('set_amenity', {
      call: function(cmdobj, fn, args) {
         if (!selected) {
            return false;
         }
         var amenity = args._[0];
         var valid_types = ["friendly", "hostile", "neutral"];
         if (!amenity || !valid_types.contains(amenity)) {
            return false;
         }

         return radiant.call_obj('stonehearth.player', 'debug_set_amenity_command', selected, amenity);
      },
      description: "Changes player amenity/relationship with the selected entity's faction (friendly, neutral, or hostile). Usage: set_amenity hostile",
      test: function(entity) {
         var player_id = entity.get('player_id');
         if (player_id && player_id != App.stonehearthClient.getPlayerId()) {
            return true;
         }
         return false;
      }
   });

   radiant.console.register('navgrid_viz', {
      call: function(cmdobj, fn, args) {
         var mode = args._[0];
         return radiant.call('radiant:navgrid_viz', mode);
      },
      description : "Enables different nav grid visualizations. Usage: navgrid_viz [navgrid | water_tight | topology | none]"
   });

   radiant.console.register('step_plan', {
      call: function(cmdobj, fn, args) {
         var mode = args._[0];
         return radiant.call_obj('stonehearth.building', 'step_plan');
      },
      description : "Step the currently selected building's plan"
   });

   // SH original function:
   // radiant.console.register('dump_building', {
   //    call: function(cmdobj, fn, args) {
   //       if (!selected) {
   //          return false;
   //       }
   //       return radiant.call_obj('stonehearth.build', 'dump_building', selected);
   //    },
   //    description : "Dumps the selected building to a qubicle file.",
   //    test: function(entity) {
   //       if (entity.get('stonehearth:building') && entity.get('stonehearth:construction_progress')) {
   //          return true;
   //       }
   //       return false;
   //    },
   //    debugMenuNameOverride: "Dump to QB"
   // });

   // ACE replacement function:
   radiant.console.register('dump_building', {
      call: function(cmdobj, fn, args) {
         // what a mess this is to get the selected building entity!
         // if/when we adjust the build view stuff, we can make this more accessible
         // if (!_buildStatusView)
         // {
         //    var gmm = App.getGameModeManager();
         //    var buildView = gmm.getView(gmm.modes.BUILD)._buildingDesignerView;
         //    radiant.each(buildView.get('childViews'), function(_, v) {
         //       if (v.templateName == 'buildingStatus') {
         //          _buildStatusView = v;
         //       }
         //    });
         // }

         // if (!_buildStatusView._current_building) {
         //    return false;
         // }

         // return radiant.call('stonehearth_ace:dump_building_command', _buildStatusView._current_building);

         return radiant.call('stonehearth_ace:dump_selected_building');
      },
      description : "Dumps the selected building to a qubicle file.",
      // test: function(entity) {
      //    if (entity.get('stonehearth:build2:building')) {
      //       return true;
      //    }
      //    return false;
      // },
      debugMenuNameOverride: "Dump to QB"
   });

   radiant.console.register('destroy_scaffolding', {
      call: function(cmdobj, fn, args) {
         var building = args._[0] || selected;
         return radiant.call_obj('stonehearth.build', 'destroy_all_scaffolding_command', building);
      },
      description : "Destroys the scaffolding for the selected building, or arg 0. Usage: destroy_scaffolding object://game/12345",
      test: function(entity) {
         if (entity.get('stonehearth:building') && entity.get('stonehearth:construction_progress')) {
            return true;
         }
         return false;
      },
      debugMenuNameOverride: "Destroy All Scaffolding"
   });

   // ACE added function:
   radiant.console.register('show_debug_ui', {
      parseString: function(string) {
         switch(string.toLowerCase()){
            case "false": case "no": case "0": case null: return false;
            case "true": case "yes": case "1": default: return true;
         }
      },

      call: function(cmdobj, fn, args) {
         var shouldShow = args._.length > 0 ? this.parseString(args._[0]) : false;
         $(top).trigger('set_debug_ui_visible', { shouldShow: shouldShow });
      },
      description: "Use to change visibility of the debugtools panel. Usage: show_debug_ui true/false"
   });
});
