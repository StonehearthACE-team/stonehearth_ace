local validator = radiant.validator

local TitlesCallHandler = class()

function TitlesCallHandler:get_titles_json_for_entity_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local pop = stonehearth.population:get_population(radiant.entities.get_player_id(entity))
   response:resolve({
      json = pop and pop:get_titles_json_for_entity(entity)
   })
end

function TitlesCallHandler:select_title_command(session, response, entity, title, rank)
   validator.expect_argument_types({'Entity', validator.optional('string'), validator.optional('number')}, entity, title, rank)

   local unit_info = entity:get_component('stonehearth:unit_info')
   if unit_info then
      unit_info:select_title(title, rank)
   end
end

return TitlesCallHandler