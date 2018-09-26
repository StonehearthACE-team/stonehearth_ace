local Point3 = _radiant.csg.Point3
local Path = _radiant.sim.Path
local FindPathToLocation = radiant.class()

FindPathToLocation.name = 'find path to location'
FindPathToLocation.does = 'stonehearth:find_path_to_location'
FindPathToLocation.args = {
   location = Point3,
   stop_when_adjacent = {
      type = 'boolean',   -- whether to stop adjacent to the location
      default = false,
   },
}
FindPathToLocation.think_output = {
   path = Path,
}
FindPathToLocation.priority = 0

FindPathToLocation._origin_region = _radiant.sim.alloc_region3()
FindPathToLocation._origin_region:modify(function(cursor)
      cursor:add_point(Point3.zero)
   end)

function FindPathToLocation:start_thinking(ai, entity, args)
   local options = {}

   if not args.stop_when_adjacent then
      -- explicitly set the adjacent region to the place we want to end up
      options.destination_region = self._origin_region
      options.adjacent_region = self._origin_region
   end

   ai:set_think_output({
         options = options,
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(FindPathToLocation)
         :execute('stonehearth:create_entity', {
            location = ai.ARGS.location,
            options = ai.PREV.options,
         })
         :execute('stonehearth:find_path_to_entity', {
            destination = ai.PREV.entity,
         })
         :set_think_output({
            path = ai.PREV.path,
         })
