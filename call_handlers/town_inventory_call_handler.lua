local validator = radiant.validator
local TownInventoryCallHandler = class()

function TownInventoryCallHandler:get_item_container(session, response, item)
   validator.expect_argument_types({'Entity'}, item)
   validator.expect.matching_player_id(session.player_id, item)

   local container = stonehearth.inventory:get_inventory(session.player_id):container_for(item)
   response:resolve({container = container})
end

function TownInventoryCallHandler:set_default_storage(session, response, item, value)
   validator.expect_argument_types({'Entity'}, item)

   local town = stonehearth.town:get_town(session.player_id)
   if value then
      town:add_default_storage(item)
   else
      town:remove_default_storage(item:get_id())
   end
end

return TownInventoryCallHandler