local Entity = _radiant.om.Entity

local PetSleepInBedAdjacent = radiant.class()

PetSleepInBedAdjacent.name = 'sleep in pet bed adjacent'
PetSleepInBedAdjacent.does = 'stonehearth_ace:pet_sleep_in_bed_adjacent'
PetSleepInBedAdjacent.args = {
   bed = Entity
}
PetSleepInBedAdjacent.priority = 0

function PetSleepInBedAdjacent:run(ai, entity, args)
   local bed = args.bed

   -- Ideally we would get the model_variant_delay from the duration of the goto_sleep animation.
   -- This is currently not exposed as the information is parsed deep in the C++ layer.
   local model_variant_delay = 160
   local mount_component = bed:add_component('stonehearth:mount')
   local success = mount_component:mount(entity, model_variant_delay)
   if not success then
      ai:abort(string.format('%s could not not mount %s', tostring(entity), tostring(bed)))
   end

   ai:execute('stonehearth:run_effect', { effect = 'idle_goto_sleep' })
   ai:execute('stonehearth:run_sleep_effect', { duration = stonehearth.constants.sleep.PET_SLEEP_DURATION })
   ai:execute('stonehearth:run_effect', { effect = 'sleep_goto_idle' })

   radiant.entities.set_resource(entity, 'sleepiness', entity:get_component('stonehearth:expendable_resources'):get_min_value('sleepiness'))
end

function PetSleepInBedAdjacent:stop(ai, entity, args)
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

return PetSleepInBedAdjacent
