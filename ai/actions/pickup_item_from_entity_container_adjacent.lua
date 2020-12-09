local Entity = _radiant.om.Entity
local PickupItemFromEntityContainerAdjacent = radiant.class()

PickupItemFromEntityContainerAdjacent.name = 'pickup item from entity container adjacent'
PickupItemFromEntityContainerAdjacent.does = 'stonehearth_ace:pickup_item_from_entity_container_adjacent'
PickupItemFromEntityContainerAdjacent.args = {
   entity = Entity      -- the container to be picked from
}
PickupItemFromEntityContainerAdjacent.priority = 0.0

--[[
   pick the object from a container on a location
   location: the coordinates of where to pick the entity from
]]
function PickupItemFromEntityContainerAdjacent:start_thinking(ai, entity, args)
   ai:set_think_output()
end

function PickupItemFromEntityContainerAdjacent:run(ai, entity, args)
   local container = args.entity -- the container

   if not radiant.entities.is_adjacent_to(entity, container) then
      ai:abort(string.format('%s is not adjacent to %s', tostring(entity), tostring(container)))
   end

   radiant.entities.turn_to_face(entity, container)
   local container_location = radiant.entities.get_world_grid_location(container)
   ai:execute('stonehearth:run_pickup_effect', { location = container_location })
   radiant.check.is_entity(entity)
   local item = entities.increment_carrying(entity, num_to_add)
   if item then
      entities.remove_child(container, item)
   end
end

return PickupItemFromEntityContainerAdjacent
