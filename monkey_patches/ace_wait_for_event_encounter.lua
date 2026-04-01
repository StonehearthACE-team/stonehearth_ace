local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local WaitForEventEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.wait_for_event_encounter'

local AceWaitForEventEncounter = class()

AceWaitForEventEncounter._ace_old_activate = WaitForEventEncounter.activate
function AceWaitForEventEncounter:activate()
   self:_ace_old_activate()

   if self._sv.tracking_bulletin then
      self:_destroy_bulletin()
   end

   if self._sv.tracking_bulletin_data then
      self:_create_tracking_bulletin()
   end
end

AceWaitForEventEncounter._ace_old_start = WaitForEventEncounter.start
function AceWaitForEventEncounter:start(ctx, info)
   self:_ace_old_start(ctx, info)

   self._sv.tracking_bulletin_data = nil
   self._sv.tracking_bulletin = nil
   local track_source = info.track_source

   if track_source then
      self._sv.tracking_bulletin_data = track_source
      self.__saved_variables:mark_changed()
      self:_create_tracking_bulletin()
   end   
end

function AceWaitForEventEncounter:_create_tracking_bulletin()
   if not self._sv.tracking_bulletin then
      local bulletin_data = self._sv.tracking_bulletin_data
      local bulletin_source = nil
      if bulletin_data and self._sv.source then
         if self._sv.is_multi then
            for _,source in pairs(self._sv.source) do
               if source and source:is_valid() then     
                  bulletin_source = source
                  break
               end
            end
         elseif self._sv.source and self._sv.source:is_valid() then
            bulletin_source = self._sv.source
         end
      end
      
      if bulletin_source then
         self._sv.tracking_bulletin = game_master_lib.create_tracking_bulletin(bulletin_source, self._sv.ctx.player_id, bulletin_data)
         self._sv.tracking_bulletin:_listen_for_target_entity_destruction()
         self.__saved_variables:mark_changed()
      end
   end
end

function AceWaitForEventEncounter:_destroy_bulletin()
   if self._sv.tracking_bulletin then
      stonehearth.bulletin_board:remove_bulletin(self._sv.tracking_bulletin)
      self._sv.tracking_bulletin = nil
   end
   
   self.__saved_variables:mark_changed()
end

AceWaitForEventEncounter._ace_old__on_event_triggered = WaitForEventEncounter._on_event_triggered
function AceWaitForEventEncounter:_on_event_triggered(ctx)
   if self._sv.tracking_bulletin then
      self:_destroy_bulletin()
   end

   self:_ace_old__on_event_triggered(ctx)
end

AceWaitForEventEncounter._ace_old_stop = WaitForEventEncounter.stop
function AceWaitForEventEncounter:stop()
   if self._sv.tracking_bulletin then
      self:_destroy_bulletins()
   end

   self:_ace_old_stop()
end

return AceWaitForEventEncounter