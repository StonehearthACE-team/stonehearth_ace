micro_world_server = {}

-- the 'radiant:new_game' event is triggered whenever a new game starts
radiant.events.listen(micro_world_server, 'radiant:new_game', function(args)
      -- read the config file for the world to use.  this will read the
      -- mods.microworld.world key, returning it's value or 'mini_game'
      -- if that key does not exist.
      local world_name = radiant.util.get_config('world', 'mini_game')

      -- generate the name of the script to load for this world from the
      -- world name.  it must be placed in the worlds directory.
      local script_name = string.format('microworld.worlds.%s_world', world_name)

      -- try to load the script.
      local script = require(script_name)
      if not script then
         error(string.format('failed to require world script "%s".', script_name))
      end

      radiant.events.listen(radiant, 'radiant:client_joined', function(args)
         --_radiant.sim.start_game()
         -- ACE: tell the game_creation service that the world has been created
         -- this will start the simulation and also set a game id so that anything that's expecting that to happen will be happy
         stonehearth.game_creation:on_world_generation_complete()
      end)

      -- the script must return a generator function which create an
      -- insteand of an object with a `start` method.
      local world = script() -- call __init on script
      if not world then
         error(string.format('world script "%s" failed to construct a world.', script_name))
      end

      -- we got a world back!  start it up!!
      if world.start then
         world:start()
      end
   end)

return micro_world_server
