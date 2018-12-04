local validator = radiant.validator
local TownInventoryCallHandler = class()

function TownInventoryCallHandler:get_item_container(session, response, item)
   validator.expect_argument_types({'Entity'}, item)
   validator.expect.matching_player_id(session.player_id, item)

   local container = stonehearth.inventory:get_inventory(session.player_id):container_for(item)
   response:resolve({container = container})
end

return TownInventoryCallHandler