local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local CreateMission = require 'stonehearth.services.server.game_master.controllers.encounters.create_mission_encounter'

local AceCreateMission = class()

local MISSION_CONTROLLER = 'stonehearth:game_master:missions:'

AceCreateMission._ace_old_start = CreateMission.start
function AceCreateMission:start(ctx, info)
   self:_ace_old_start(ctx, info)
   self._sv.alert_bulletin = nil
end

AceCreateMission._ace_old_stop = CreateMission.stop
function AceCreateMission:stop()
   if self._sv.alert_bulletin then
      self._sv.alert_bulletin:destroy()
      self._sv.alert_bulletin = nil
   end

   self:_ace_old_stop()
end

function AceCreateMission:_start_mission(op, location)
   local info = self._sv.info
   if op == 'abort' then
      local on_searcher_failure = info.on_searcher_failure

      -- ACE: create a notification if searcher fails
      if on_searcher_failure and on_searcher_failure.notification then        
         stonehearth.bulletin_board:post_bulletin(self._sv.ctx.player_id)
            :set_ui_view('StonehearthGenericBulletinDialog')
            :set_callback_instance(self)
            :set_data({
               title = on_searcher_failure.notification.title,
               message = on_searcher_failure.notification.message,
               ok_callback = '_on_bulletin_ok',
            })
      end

      -- Retry after some delay if specified in json
      if on_searcher_failure and on_searcher_failure.retry then
         self._sv.timer = stonehearth.calendar:set_persistent_timer("Retry AceCreateMission",
                                                                     stonehearth.constants.encounters.DEFAULT_SEARCHER_DELAY,
                                                                     radiant.bind(self, '_create_searcher'))
      -- Destroy the tree starting at specified root
      elseif on_searcher_failure and on_searcher_failure.destroy_tree then
         local root_node = on_searcher_failure.destroy_tree.root
         if root_node then
            game_master_lib.destroy_tree(root_node, on_searcher_failure.destroy_tree.destroy_root, self._sv.ctx)
         end
      else
      -- Destroy this node if no location was found and searcher failure options were not specified
         self:_destroy_node()
      end
   else
      local ctx = self._sv.ctx

      assert(info.mission)
      assert(info.mission.role)

      ctx.enemy_location = location

      local mission_controller_name = MISSION_CONTROLLER .. info.mission.role
      local mission = radiant.create_controller(mission_controller_name, info)
      assert(mission)

      self._sv.mission = mission
      mission:start(ctx, info.mission)

      -- all done!  trigger the next guy
      ctx.arc:trigger_next_encounter(ctx)
   end
end

function AceCreateMission:_on_bulletin_ok()
   if self._sv.alert_bulletin then
      self._sv.alert_bulletin:destroy()
      self._sv.alert_bulletin = nil
   end
end

return AceCreateMission