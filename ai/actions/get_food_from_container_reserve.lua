local Entity = _radiant.om.Entity
local GetFoodFromContainerReserve = class()

GetFoodFromContainerReserve.name = 'get food from container reserve'
GetFoodFromContainerReserve.does = 'stonehearth_ace:get_food_from_container'
GetFoodFromContainerReserve.args = {
   container = Entity,
   storage = {
      type = Entity,
      default = stonehearth.ai.NIL,
   }
}
GetFoodFromContainerReserve.priority = 0

function GetFoodFromContainerReserve:start_thinking(ai, entity, args)
   local container = args.container
   if container and container:is_valid() then
      local data = radiant.entities.get_entity_data(container, 'stonehearth:food_container')
      if data and data.require_reservation then
         ai:set_think_output({})
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(GetFoodFromContainerReserve)
         :execute('stonehearth:reserve_entity', {
            entity = ai.ARGS.container,
            reserve_from_self = true,
         })
         :execute('stonehearth:get_food_from_container_adjacent', {
            container = ai.ARGS.container,
            storage = ai.ARGS.storage,
         })
