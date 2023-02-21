local Entity = _radiant.om.Entity
local GetDrinkFromContainerNoReserve = class()

GetDrinkFromContainerNoReserve.name = 'get drink from container reserve'
GetDrinkFromContainerNoReserve.does = 'stonehearth_ace:get_drink_from_container'
GetDrinkFromContainerNoReserve.args = {
   container = Entity,
   storage = {
      type = Entity,
      default = stonehearth.ai.NIL,
   }
}
GetDrinkFromContainerNoReserve.priority = 0

function GetDrinkFromContainerNoReserve:start_thinking(ai, entity, args)
   local container = args.container
   if container and container:is_valid() then
      local data = radiant.entities.get_entity_data(container, 'stonehearth_ace:drink_container')
      if data and not data.require_reservation then
         ai:set_think_output({})
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkFromContainerNoReserve)
         :execute('stonehearth_ace:get_drink_from_container_adjacent', {
            container = ai.ARGS.container,
            storage = ai.ARGS.storage,
         })
