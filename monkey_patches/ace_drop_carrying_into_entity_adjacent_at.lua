-- ACE: just overriding the mob:get_facing bit to use ace_entities.get_facing to avoid asserts with tilted entities

local Point3 = _radiant.csg.Point3

local AceDropCarryingIntoEntityAdjacentAt = radiant.class()

--[[
   Like drop_carrying_into_entity_adjacent, except that we pick what location in
   the target to put the object we're dropping. And we run the a specified drop animation
   instead of the normal drop animation.
]]
function AceDropCarryingIntoEntityAdjacentAt:start_thinking(ai, entity, args)
   -- todo: ASSERT we're adjacent!
   -- if the target is not a table, then just return
   local container = args.entity
   local container_entity_data = radiant.entities.get_entity_data(container, 'stonehearth:table')
   if not container_entity_data then
      return
   end
   local offset = container_entity_data['drop_offset']
   if offset then
      local facing = radiant.entities.get_facing(args.entity)
      local offset = Point3(offset.x, offset.y, offset.z)
      self._drop_offset = offset:rotated(facing)
   end
   self._drop_effect = container_entity_data['drop_effect']
   if not self._drop_effect then
      self._drop_effect = 'carry_putdown_on_table'
   end

   ai:set_think_output()
end

return AceDropCarryingIntoEntityAdjacentAt
