local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
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

-- ACE: don't destroy the old one and create a new one, that's insane
-- just remove the existing one from the world and place its iconic at that location
-- (and "reset" health/debuffs on the entity)
function AcePlaceItemCallHandler:undeploy_golem(session, response, item)
   validator.expect_argument_types({'Entity'}, item)

   -- check and see if this item is already claimed; if not, it's ours now
   if not radiant.entities.get_player_id(item) or radiant.entities.get_player_id(item) == '' then
      radiant.entities.set_player_id(item, session.player_id)
   end
   
   local location = radiant.entities.get_world_grid_location(item)
   local root_form, iconic_form = entity_forms_lib.get_forms(item)
   if location and iconic_form then
      radiant.terrain.remove_entity(item)
      radiant.terrain.place_entity_at_exact_location(iconic_form, location)
      radiant.effects.run_exact_effect(iconic_form, 'stonehearth:effects:fursplosion_effect')

      -- reset health and debuffs
      radiant.entities.reset_health(item, true)

      return true
   end
   return false
end

return AcePlaceItemCallHandler
