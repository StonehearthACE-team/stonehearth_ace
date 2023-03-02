local ItemPlacer = require 'stonehearth.services.client.build_editor.item_placer'
local validator = radiant.validator

--local PlaceItemCallHandler = require 'stonehearth.call_handlers.place_item_call_handler'
local AcePlaceItemCallHandler = class()

function AcePlaceItemCallHandler:choose_place_item_type_location(session, response, item_to_place, quality, transactional, options)
   validator.expect_argument_types({'string', validator.optional('number'), validator.optional('boolean'), validator.optional('table')},
         item_to_place, quality, transactional, options)

   -- This will register the tool; no need to hold on to the variable....
   local item_placer = ItemPlacer():go(session, response, item_to_place, quality, transactional, options)
end

return AcePlaceItemCallHandler
