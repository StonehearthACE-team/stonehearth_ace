local Entity = _radiant.om.Entity
local GetDrinkFromContainerReserve = class()

GetDrinkFromContainerReserve.name = 'get drink from container reserve'
GetDrinkFromContainerReserve.does = 'stonehearth_ace:get_drink_from_container'
GetDrinkFromContainerReserve.args = {
   container = Entity,
}
GetDrinkFromContainerReserve.priority = 0

function GetDrinkFromContainerReserve:start_thinking(ai, entity, args)
   local container = args.container
   if container and container:is_valid() then
      local data = radiant.entities.get_entity_data(container, 'stonehearth_ace:drink_container')
      if data and data.require_reservation then
         ai:set_think_output({})
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(GetDrinkFromContainerReserve)
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.ARGS.container
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.container })
         :execute('stonehearth_ace:get_drink_from_container_adjacent', { container = ai.ARGS.container })