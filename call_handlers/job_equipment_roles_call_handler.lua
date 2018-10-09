local validator = radiant.validator
local JobRolesCallHandler = class()

function JobRolesCallHandler:change_job_equipment_role(session, response, entity, current_role)
   validator.expect_argument_types({'Entity', 'string'}, entity, current_role)
   validator.expect.matching_player_id(session.player_id, entity)

   local job = entity:get_component('stonehearth:job')
   if not job then
      return false
   end

   local role = job:set_next_equipment_role(current_role)
   if not role then
      return false
   end

   return true
end

return JobRolesCallHandler
