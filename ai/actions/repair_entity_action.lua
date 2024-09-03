-- the base game version of this specifically repairs siege weapons
-- we want to allow crafters to repair any item that their job can craft
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local get_root_entity = function(item)
   return entity_forms.get_root_entity(item) or item
end

local RepairEntity = radiant.class()

RepairEntity.name = 'repair entity'
RepairEntity.does = 'stonehearth:repair'
RepairEntity.status_text_key = 'stonehearth_ace:ai.actions.status_text.repair'
RepairEntity.args = {}
RepairEntity.priority = {0, 1}

function RepairEntity:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)
   local job = entity:add_component('stonehearth:job')
   local job_uri = job:get_job_uri()
   local job_infos = {}
   local job_controller = job:get_curr_job_controller()
   local can_repair_as_any_job = job_controller:can_repair_as_any_job()
   local can_repair_as_job = radiant.util.merge_into_table({ [job_uri] = true }, job_controller:get_can_repair_as_jobs())
   local can_repair_array = {}

   -- we want to always report the job uris in the same order for caching purposes, so add to an array and sort
   for uri, can_repair in pairs(can_repair_as_job) do
      if can_repair then
         table.insert(can_repair_array, uri)
      end
   end
   table.sort(can_repair_array)

   local key = player_id .. '|' .. tostring(can_repair_as_any_job)
   for _, uri in ipairs(can_repair_array) do
      key = key .. '|' .. uri
      job_infos[uri] = stonehearth.job:get_job_info(player_id, uri)
   end

   -- if the item specifies a repairable_by_job table, compare that to this entity's can_repair_as_job table
   -- if there's a true match, we're good
   -- if there's no match, check any of the non-false matches for if that job can craft the item
   local is_repairable = function(item, repairable_by_job)
      for uri, repairable in pairs(repairable_by_job) do
         if repairable and can_repair_as_job[uri] then
            return true
         end
      end

      for _, uri in ipairs(can_repair_array) do
         if job_infos[uri]:job_can_craft(get_root_entity(item):get_uri()) then
            return true
         end
      end

      return false
   end

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
         if entity_data.repairable_by_any_job == false then
            return false
         elseif not can_repair_as_any_job and not is_repairable(item, entity_data.repairable_by_job or {}) then
            return false
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

   -- prioritize repairing structural entities, deprioritize training dummies
   local rating_fn = function(item)
         if item:get_component('stonehearth_ace:training_dummy') then
            return 0
         else
            return 1
         end
      end

   ai:set_think_output({
      filter_fn = filter_fn,
      rating_fn = rating_fn,
      owner_player_id = player_id,
   })
end

function RepairEntity:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type') * 0.8
        + child_utilities:get('stonehearth:follow_path') * 0.2
end

local ai = stonehearth.ai
return ai:create_compound_action(RepairEntity)
         :execute('stonehearth:abort_on_event_triggered', { -- abort on job change to switch up the repairable-by-job filter
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', { -- abort on job change to switch up the repairable-by-job filter
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:repair_capabilities_changed',
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(4).filter_fn,
            rating_fn = ai.BACK(4).rating_fn,
            description = 'find a siege object to run to',
            owner_player_id = ai.BACK(4).owner_player_id,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(6).filter_fn,
            item = ai.BACK(2).item,
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.BACK(3).path,
            stop_distance = 3
         })
         :execute('stonehearth:repair_entity_adjacent', {
            entity = ai.BACK(5).item
         })
