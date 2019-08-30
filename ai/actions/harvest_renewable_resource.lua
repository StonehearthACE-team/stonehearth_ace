local HarvestRenewableResource = radiant.class()

HarvestRenewableResource.name = 'harvest renewable resource'
HarvestRenewableResource.does = 'stonehearth:harvest_renewable_resource'
HarvestRenewableResource.args = {
   category = 'string',  -- The category for resource harvesting
}
HarvestRenewableResource.priority = {0, 1}

-- TODO: Share these with harvest_resource_node.
local function _harvest_filter_fn(player_id, category, item)
   if not item or not item:is_valid() then
      return false
   end

   local renewable_resource = item:get_component('stonehearth:renewable_resource_node')
   if not renewable_resource or not renewable_resource:is_harvestable() then
      return false
   end

   local task_tracker_component = item:get_component('stonehearth:task_tracker')
   if not task_tracker_component then
      return false
   end

   local buffs = item:get_component('stonehearth:buffs')
   if buffs and buffs:has_buff('stonehearth:buffs:sleeping') then
      return false
   end

   return task_tracker_component:is_task_requested(player_id, category, HarvestRenewableResource.does)
end

local function _harvest_rating_fn(desires_tracker, item)
   if desires_tracker then
      local node = item:get_component('stonehearth:renewable_resource_node')
      local resource = node:get_harvested_item_uri()
      if resource then
         return desires_tracker:get_item_or_resource_need_score(resource)
      end
   end
   return 0
end

function HarvestRenewableResource:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local category = args.category

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:harvest_renewable_resource', work_player_id .. ':' .. category, function(item)
         return _harvest_filter_fn(work_player_id, category, item)
      end)
      
   local desires_tracker = stonehearth.inventory:get_inventory(work_player_id):get_desires()
   local rating_fn = function(item)
         return _harvest_rating_fn(desires_tracker, item)
      end

   if not ai.CURRENT.carrying then
      ai:set_think_output({
         harvest_filter_fn = filter_fn,
         harvest_rating_fn = rating_fn,
         owner_player_id = work_player_id,
      })
   end
end

function HarvestRenewableResource:compose_utility(entity, self_utility, child_utilities, current_activity)
   return self_utility * 0.9 + child_utilities:get('stonehearth:follow_path') * 0.1
end

local ai = stonehearth.ai
return ai:create_compound_action(HarvestRenewableResource)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:wait_for_town_inventory_space', {
            owner_player_id = ai.BACK(2).owner_player_id,
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(3).harvest_filter_fn,
            rating_fn = ai.BACK(3).harvest_rating_fn,
            description = 'finding harvestable nodes (renewable)',
            owner_player_id = ai.BACK(3).owner_player_id,
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).harvest_filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).item,
            owner_player_id = ai.BACK(5).owner_player_id,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(8).harvest_filter_fn,
            item = ai.BACK(5).item,
         })
         :execute('stonehearth:add_buff', {
            buff = 'stonehearth:buffs:stopped',
            target = ai.BACK(6).item
         })
         :execute('stonehearth:harvest_renewable_resource_adjacent', {
            resource = ai.BACK(7).item,
            owner_player_id = ai.BACK(10).owner_player_id,
         })
