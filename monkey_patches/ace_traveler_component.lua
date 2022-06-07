local AceTravelerComponent = class()

-- if an assigned bed is upgraded, update the reference and redo the sleep action
function AceTravelerComponent:update_bed(bed)
   if self._sv._bed then
      self._sv._bed = bed
      self:_go_to_sleep()
   end
end

-- ACE: save the task so we can destroy it and recreate it if we need to update the bed
function AceTravelerComponent:_go_to_sleep()
   if self._sleep_alarm then
      self._sleep_alarm:destroy()
      self._sleep_alarm = nil
   end

   if not self._sv._bed then
      self._sv._bed = stonehearth.traveler:assign_bed(self._entity)
   end
   if self._sv._bed then
      if self._sleep_task then
         self._sleep_task:destroy()
      end
      local player_id = stonehearth.traveler:get_assigned_town(self._entity):get_player_id()
      self._sleep_task = self._entity:get_component('stonehearth:ai')
         :get_task_group('stonehearth:task_groups:traveler')
         :create_task('stonehearth:sleep', {owner_player_id = player_id})
            :once()
            :notify_completed(function() self:_on_wake_up() end)
            :start()
   end
   -- if sleeping, this won't kick in until waking up anyway, but helps
   -- in case sleeping is interrrupted
   self._sv._time_to_leave = true
end

return AceTravelerComponent
