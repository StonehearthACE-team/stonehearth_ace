-- @title stonehearth:drop_carrying_adjacent
-- @book reference
-- @section activities

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local DropCarryingAdjacent = radiant.class()

--[[ @markdown
Use stonehearth:drop\_carrying\_adjacent when the entity must

a.) put what it is carrying down at a specific location in the world and

b.) when the entity is already standing beside that location.

This action is usually used as part of a compound action, and prefaced with an action requring the entity to move to a location beside the target drop location.

For example,  _move\_item\_to\_available\_stockpile_ and _restock\_items\_in\_backpack_ call ai:execute('stonehearth:drop\_carrying\_adjacent') after various go\_to\_location calls.

stonehearth:drop\_carrying\_adjacent is only implemented by the drop\_carrying\_adjacent\_action.lua file:
]]--

DropCarryingAdjacent.name = 'drop carrying adjacent'
DropCarryingAdjacent.does = 'stonehearth:drop_carrying_adjacent'
DropCarryingAdjacent.args = {
   location = Point3,      -- where to drop it
   ignore_missing = {
      type = 'boolean',
      default = false,
   },
}
DropCarryingAdjacent.think_output = {
   item = Entity,          -- what got dropped
}
DropCarryingAdjacent.priority = 0

-- Only set think output if we are actually carrying something
function DropCarryingAdjacent:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying ~= nil then
      -- todo: ASSERT we're adjacent!
      local carrying = ai.CURRENT.carrying
      ai.CURRENT.carrying = nil
      ai:set_think_output({ item = carrying })
   end
end

-- Double check that we are carrying and adjacent to the target location before dropping the item
function DropCarryingAdjacent:run(ai, entity, args)
   local location = args.location

   radiant.check.is_entity(entity)
   radiant.check.is_a(location, Point3)

   if not radiant.entities.get_carrying(entity) then
      if not args.ignore_missing then
         ai:abort('cannot drop item not carrying one!')
      end
      return
   end

   local entity_location = radiant.entities.get_world_grid_location(entity)
   if entity_location ~= location and not radiant.entities.location_within_reach(entity, location, entity_location) then
      ai:abort(string.format('%s drop location %s is not within reach from %s', tostring(entity), tostring(location), tostring(entity_location)))
      return
   end

   radiant.entities.turn_to_face(entity, location)
   ai:execute('stonehearth:run_putdown_effect', { location = location })
   radiant.entities.drop_carrying_on_ground(entity, location)
end

return DropCarryingAdjacent
