local periodic_interaction_lib = {}

-- shouldn't need to create a listener for the periodic interaction entity itself changing mode/requirements
-- because when that happens, it will destroy and recreate tasks as necessary
function periodic_interaction_lib.create_usability_listeners(entity, pi_item, reconsider_cb)
   local listeners = {}

   local pi_comp = pi_item and pi_item:is_valid() and pi_item:get_component('stonehearth_ace:periodic_interaction')
   if pi_comp then
      local requirements = pi_comp:get_current_mode_requirements()
      if requirements then
         -- if there's a level requirement, we need a job level listener
         -- but we abort on job change, so if we're not even that job yet, we don't need it
         -- also levels don't decrease, so we only need the listener if we're below the required level
         if requirements.job then
            local job_component = entity:get_component('stonehearth:job')
            if job_component and job_component:get_job_uri() == requirements.job and requirements.level and job_component:get_current_job_level() < requirements.level then
               table.insert(listeners, radiant.events.listen(entity, 'stonehearth:level_up', function()
                     if job_component:get_current_job_level() >= requirements.level then
                        reconsider_cb()
                     end
                  end))
            end
         end

         -- any time equipment is changed, a required item could be getting added or removed
         if requirements.any_equipped_item then
            table.insert(listeners, radiant.events.listen(entity, 'stonehearth:equipment_changed', reconsider_cb))
         end

         -- need to reconsider any time a required buff is added or removed
         -- buffs are added and removed all the time, so it's good to filter here
         if requirements.any_active_buff then
            local buffs = requirements.any_active_buff
            if type(buffs) == 'string' then
               buffs = {buffs}
            end

            table.insert(listeners, radiant.events.listen(entity, 'stonehearth:buff_added', function(args)
                  for _, buff in ipairs(buffs) do
                     if args.uri == buff then
                        reconsider_cb()
                        break
                     end
                  end
               end))

            table.insert(listeners, radiant.events.listen(entity, 'stonehearth:buff_removed', function(uri)
                  for _, buff in ipairs(buffs) do
                     if uri == buff then
                        reconsider_cb()
                        break
                     end
                  end
               end))
         end
      end
   end

   return listeners
end

return periodic_interaction_lib
