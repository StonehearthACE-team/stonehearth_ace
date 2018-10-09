local validator = radiant.validator
local AutoHarvestCallHandler = class()

function AutoHarvestCallHandler:toggle_auto_harvest(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)
   validator.expect.matching_player_id(session.player_id, entity)

   local renewable = entity:get_component('stonehearth:renewable_resource_node')
   if renewable then
      local enabled = renewable:get_auto_harvest_enabled()
      renewable:set_auto_harvest_enabled(not enabled)
   end
end

return AutoHarvestCallHandler