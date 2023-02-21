local Entity = _radiant.om.Entity
local GetFoodFromContainerNoReserve = class()

GetFoodFromContainerNoReserve.name = 'get food from container no reserve'
GetFoodFromContainerNoReserve.does = 'stonehearth_ace:get_food_from_container'
GetFoodFromContainerNoReserve.args = {
   container = Entity,
   storage = {
      type = Entity,
      default = stonehearth.ai.NIL,
   }
}
GetFoodFromContainerNoReserve.priority = 0

function GetFoodFromContainerNoReserve:start_thinking(ai, entity, args)
   local container = args.container
   if container and container:is_valid() then
      local data = radiant.entities.get_entity_data(container, 'stonehearth:food_container')
      if data and not data.require_reservation then
         ai:set_think_output({})
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(GetFoodFromContainerNoReserve)
         :execute('stonehearth:get_food_from_container_adjacent', {
            container = ai.ARGS.container,
            storage = ai.ARGS.storage,
         })
