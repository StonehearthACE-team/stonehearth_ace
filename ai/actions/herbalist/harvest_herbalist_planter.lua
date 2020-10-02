local HarvestHerbalistPlanter = radiant.class()

HarvestHerbalistPlanter.name = 'harvest herbalist planter'
HarvestHerbalistPlanter.does = 'stonehearth_ace:harvest_herbalist_planter'
HarvestHerbalistPlanter.args = {}
HarvestHerbalistPlanter.priority = {0, 1}

-- TODO: Share these with harvest_resource_node.
local function _harvest_filter_fn(player_id, item)
   if not item or not item:is_valid() then
      return false
   end

   local planter = item:get_component('stonehearth_ace:herbalist_planter')
   return planter and planter:is_harvestable()
end

local function _harvest_rating_fn(desires_tracker, item)
   local rating = 0
   local planter = item:get_component('stonehearth_ace:herbalist_planter')
   if planter then
      local resource = planter:get_product_uri()
      if resource then
         rating = planter:get_unit_crop_level()

         if desires_tracker then
            rating = rating * 0.2 + desires_tracker:get_item_or_resource_need_score(resource) * 0.8
         end
      end
   end
   return rating
end

function HarvestHerbalistPlanter:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:harvest_herbalist_planter', player_id, function(item)
         return _harvest_filter_fn(player_id, item)
      end)
      
   local desires_tracker = stonehearth.inventory:get_inventory(player_id):get_desires()
   local rating_fn = function(item)
         return _harvest_rating_fn(desires_tracker, item)
      end

   if not ai.CURRENT.carrying then
      ai:set_think_output({
         harvest_filter_fn = filter_fn,
         harvest_rating_fn = rating_fn,
         owner_player_id = player_id
      })
   end
end

function HarvestHerbalistPlanter:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(HarvestHerbalistPlanter)
         :execute('stonehearth:wait_for_town_inventory_space')
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).harvest_filter_fn,
            rating_fn = ai.BACK(2).harvest_rating_fn,
            description = 'finding harvestable herbalist planters',
            owner_player_id = ai.BACK(2).owner_player_id
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(3).harvest_filter_fn,
            item = ai.BACK(1).item
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).item
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth_ace:harvest_herbalist_planter_adjacent', {
            planter = ai.BACK(5).item
         })
