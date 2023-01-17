local validator = radiant.validator

local QuestCallHandler = class()

function QuestCallHandler:dump_quest_storage_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)
   validator.expect.matching_player_id(session.player_id, entity)

   local quest_storage = entity:get_component('stonehearth_ace:quest_storage')
   if quest_storage then
      quest_storage:set_enabled(false)
      quest_storage:dump_items()
   end
end

return QuestCallHandler
