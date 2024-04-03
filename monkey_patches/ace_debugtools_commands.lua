local Point3 = _radiant.csg.Point3
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local AceCommands = class()

function AceCommands:create_and_place_entity(session, response, uri, iconic, timesNine, quality)
   local entity = radiant.entities.create_entity(uri)
   local entity_forms = entity:get_component('stonehearth:entity_forms')

   if iconic and entity_forms ~= nil then
      entity = entity_forms:get_iconic_entity()
   end

   stonehearth.selection:deactivate_all_tools()
   stonehearth.selection:select_location()
      :set_cursor_entity(entity)
      :done(function(selector, location, rotation)
               if timesNine == true then
                  for x=-1,1 do
                     for z=-1,1 do
                        --leave the center one (+0,0) to the call outside the loop, so that it can clean up the entity
                        if x~=0 or z~=0 then
                           _radiant.call('debugtools:create_entity', uri, iconic, location + Point3(x,0,z), rotation, quality)
                        end
                     end
                  end
               end

               _radiant.call('debugtools:create_entity', uri, iconic, location, rotation, quality)
                  :done(function()
                     radiant.entities.destroy_entity(entity)
                     response:resolve(true)
                  end)
            end)
      :fail(function(selector)
            selector:destroy()
            response:reject('no location')
         end)
      :always(function()
         end)
      :go()
end

function AceCommands:create_entity(session, response, uri, iconic, location, rotation, quality)
   local entity = radiant.entities.create_entity(uri, { owner = session.player_id })
   if quality and quality > 1 then
      item_quality_lib.apply_quality(entity, quality)
   end

   local entity_forms = entity:get_component('stonehearth:entity_forms')

   if entity_forms == nil then
      iconic = false
   end

   radiant.terrain.place_entity(entity, location, { force_iconic = iconic })
   radiant.entities.turn_to(entity, rotation)
   local inventory = stonehearth.inventory:get_inventory(session.player_id)
   if inventory and not inventory:contains_item(entity) then
      inventory:add_item(entity)
   end

   return true
end

function AceCommands:promote_to_command(session, response, entity, job, desired_level)
   if not job then
      response:reject('Failed: No job name provided.')
      return 
   end

   -- ACE: also add shortcuts for ACE-specific jobs
   local ace_jobs = {
      brewer = true,
      grower = true,
      artificer = true,
      magmasmith = true,
      scout = true,
      guardian = true,
      berserker = true,
   }
   if ace_jobs[job] then
      job = 'stonehearth_ace:jobs:' .. job
   elseif not string.find(job, ':') and not string.find(job, '/') then
      -- as a convenience for autotest writers, stick the stonehearth:job on
      -- there if they didn't put it there to begin with
      job = 'stonehearth:jobs:' .. job
   end

   --radiant.entities.drop_carrying_on_ground(entity) 
   local job_component = entity:get_component('stonehearth:job')
   if(job_component) then

      local skip_visual_effects = (desired_level and desired_level > 1) --if a level was provided, assume that will pop a dialog instead
      job_component:promote_to(job, {skip_visual_effects=skip_visual_effects})  --skipping visual effects also skips the "X became a Y!" announcement

      if desired_level then
         local current_level = job_component:get_current_job_level()
         local num_levelups_required = desired_level - current_level;

         --condition starts false if we're already at/above desired level
         for i=1, num_levelups_required do
            local hide_effects = (i ~= num_levelups_required) --only show effects and announcement for final levelup. true = hide effects for some reason
            job_component:level_up(hide_effects) 
         end
      end
   else
      response:reject('Failed: Selected entity has no job data: ' .. tostring(entity))
      return 
   end

   return true
end

return AceCommands
