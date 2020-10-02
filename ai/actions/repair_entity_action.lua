-- the base game version of this specifically repairs siege weapons
-- we want to allow crafters to repair any item that their job can craft
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local get_root_entity = function(item)
   return entity_forms.get_root_entity(item) or item
end

local RepairEntity = radiant.class()

RepairEntity.name = 'repair entity'
RepairEntity.does = 'stonehearth:repair'
RepairEntity.args = {}
RepairEntity.priority = 0

function RepairEntity:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)
   local job = entity:add_component('stonehearth:job')
   local job_uri = job:get_job_uri()
   local job_info = stonehearth.job:get_job_info(player_id, job_uri)
   local key = player_id .. '|' .. job_uri

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:repair', key, function(item)
         if not item or not item:is_valid() then
            return false
         end
         if radiant.entities.get_player_id(item) ~= player_id then
            return false -- object doesn't belong to us
         end
         local entity_data = radiant.entities.get_entity_data(item, 'stonehearth:siege_object')
         local attributes_component = item:get_component('stonehearth:attributes')
         if not entity_data or not attributes_component then
            return false -- not a siege object
         end

         -- make sure entity is craftable by this job (or specifies that it's repairable by it)
         -- setting fields to false specifically makes them not repairable even if they otherwise could be crafted by that/any job
         if entity_data.repairable_by_any_job == false or (entity_data.repairable_by_job and entity_data.repairable_by_job[job_uri] == false) then
            return false
         elseif entity_data.repairable_by_any_job == nil or not entity_data.repairable_by_job or entity_data.repairable_by_job[job_uri] == nil then
            if not job_info:job_can_craft(get_root_entity(item):get_uri()) then
               return false
            end
         end

         local percentage = radiant.entities.get_health_percentage(item)
         -- repair if the target is missing health
         if percentage and percentage < 1 then
            return true
         end

         local siege_weapon_component = item:get_component('stonehearth:siege_weapon')
         if siege_weapon_component and siege_weapon_component:needs_refill() then
            return true
         end
         return false
      end)

   ai:set_think_output({ filter_fn = filter_fn })
end

local ai = stonehearth.ai
return ai:create_compound_action(RepairEntity)
         :execute('stonehearth:abort_on_event_triggered', { -- abort on job change to switch up the repairable-by-job filter
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:find_path_to_entity_type', {
            filter_fn = ai.BACK(3).filter_fn,
            description = 'find a siege object to run to',
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).filter_fn,
            item = ai.BACK(1).destination,
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).destination
         })
         :execute('stonehearth:follow_path', {
            path = ai.BACK(3).path,
            stop_distance = 3
         })
         :execute('stonehearth:repair_entity_adjacent', {
            entity = ai.BACK(4).destination
         })
