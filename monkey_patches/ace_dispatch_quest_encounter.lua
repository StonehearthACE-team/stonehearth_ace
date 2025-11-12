local AceDispatchQuest = class()
local DispatchQuest = require 'stonehearth.services.server.game_master.controllers.encounters.dispatch_quest_encounter'

function AceDispatchQuest:start(ctx, info)
   self._sv.ctx = ctx
   self._sv._info = info

   -- Backward-compatibility.
   if info.required_job or info.required_job_level then
      info.requirements = { { job =  info.required_job, job_level = info.required_job_level } }
   elseif not info.requirements then
      info.requirements = { { } }
   end

   local opt_view = 'StonehearthDispatchQuestBulletinDialog'
   self._sv.bulletin_data = info
   self._sv.bulletin_data.on_try_dispatch = '_on_try_dispatch'
   self._sv.bulletin_data.on_abandon = '_on_abandon'

   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
                                    :set_callback_instance(self)
                                    :set_sticky(true)
                                    :set_close_on_handle(false)
                                    :set_type(info.bulletin_type or 'quest_dispatch')

   self._sv.bulletin:set_data(self._sv.bulletin_data)
                    :set_ui_view(opt_view)
   self.__saved_variables:mark_changed()
end

AceDispatchQuest._ace_old__check_requirements = DispatchQuest._check_requirements
function AceDispatchQuest:_check_requirements(citizen, requirements)
   self:_ace_old__check_requirements(citizen, requirements)

   if requirements.role then
      local job = citizen:get_component('stonehearth:job')
      if job:has_role(requirements.role) then
         if requirements.job_level then
            return job:get_current_job_level() >= requirements.job_level
         else
            return true  -- right roles and no level requirement
         end
      else
         return false  -- not the right role
      end
   else
      return true
   end
end

return AceDispatchQuest
