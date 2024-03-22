local validator = radiant.validator
local CraftingCallHandler = class()

function CraftingCallHandler:toggle_secondary_order_list_pause(session, response, job_alias)
   validator.expect_argument_types({'string'}, job_alias)

   local job_info = stonehearth.job:get_job_info(session.player_id, job_alias)
   local order_list = job_info and job_info:get_order_list()
   if order_list and order_list.toggle_secondary_list_pause then
      order_list:toggle_secondary_list_pause()
      return true
   end
end

return CraftingCallHandler
