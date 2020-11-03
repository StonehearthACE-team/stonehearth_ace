local AceSleepInCurrentBed = radiant.class()

function AceSleepInCurrentBed:stop(ai, entity, args)
   local sleepiness_observer = radiant.entities.get_observer(entity, 'stonehearth:observers:sleepiness')
   sleepiness_observer:finish_sleeping()

   -- don't need to get out of bed if we're incapacitated
   local incapacitation = entity:get_component('stonehearth:incapacitation')
   if incapacitation and incapacitation:is_incapacitated() then
      return
   end
   
   local bed = args.bed

   if bed:is_valid() then
      local mount_component = bed:add_component('stonehearth:mount')
      -- If we started running, but someone has already taken the chair, we'll abort, which calls stop().
      -- So if the bed is in use, but not by us, do nothing.
      if mount_component:is_in_use() and mount_component:get_user() == entity then
         mount_component:dismount()
      end
   end
end

return AceSleepInCurrentBed
