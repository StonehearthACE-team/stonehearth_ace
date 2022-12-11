local WorkAtStall = class()

WorkAtStall.name = 'work at stall'
WorkAtStall.does = 'stonehearth_ace:merchant:work_at_stall'
WorkAtStall.args = {}
WorkAtStall.priority = 1

local function _make_tier_stall_filter_fn(owner_id, min_tier, merchant_id)
   return function(item)
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         local stall_data = radiant.entities.get_component_data(item, 'stonehearth_ace:market_stall')
         if not stall_data or not stall_data.tier or stall_data.tier < min_tier then
            return false
         end
         
         -- make sure it's not already set up for another merchant
         local stall_component = item:get_component('stonehearth_ace:market_stall')
         if stall_component then
            local active_merchant = stall_component:get_merchant()
            if not active_merchant or not active_merchant:is_valid() or active_merchant:get_id() == merchant_id then
               return true
            end
         end

         return false
      end
end

local function _make_unique_stall_filter_fn(owner_id, uri, merchant_id)
   return function(item)
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         if item:get_uri() ~= uri then
            return false
         end

         -- make sure it's not already set up for another merchant
         local stall_component = item:get_component('stonehearth_ace:market_stall')
         if stall_component then
            local active_merchant = stall_component:get_merchant()
            if not active_merchant or not active_merchant:is_valid() or active_merchant:get_id() == merchant_id then
               return true
            end
         end

         return false
      end
end

local function _make_stall_rating_fn(merchant_id, tier_rating_fn)
   return function(item)
      -- first check if it's currently set up for this merchant
      local stall_component = item:get_component('stonehearth_ace:market_stall')
      if stall_component then
         local active_merchant = stall_component:get_merchant()
         if active_merchant and active_merchant:get_id() == merchant_id then
            return 1
         end
      end
      if tier_rating_fn then
         return tier_rating_fn(item)
      end
      return 0
   end
end

local function _make_tier_stall_rating_fn(min_tier)
   return function(item)
         local stall_data = radiant.entities.get_component_data(item, 'stonehearth_ace:market_stall')
         return min_tier / stall_data.tier
      end
end

function WorkAtStall:start_thinking(ai, entity, args)
   -- find an appropriate stall to work at
   -- if we need a specific uri stall, go for that
   -- if we need a specific tier, try to find one at least that tier, preferring the lowest possible
   -- require a stall to either be unoccupied or set to this merchant already
   local merchant_component = entity:get_component('stonehearth_ace:merchant')
   if merchant_component and not merchant_component:should_depart() then
      local filter_fn, rating_fn
      local owner_id = merchant_component:get_player_id()
      local entity_id = entity:get_id()
      local required_stall = merchant_component:get_required_stall()
      if required_stall then
         filter_fn = stonehearth.ai:filter_from_key(
               'stonehearth_ace:merchant:work_at_stall',
               owner_id .. '|' .. entity_id .. '|' .. required_stall,
               _make_unique_stall_filter_fn(owner_id, required_stall, entity_id))
         rating_fn = _make_stall_rating_fn(entity_id)
      else
         local min_stall_tier = merchant_component:get_stall_tier()
         filter_fn = stonehearth.ai:filter_from_key(
               'stonehearth_ace:merchant:work_at_stall',
               owner_id .. '|' .. entity_id .. '|' .. tostring(min_stall_tier),
               _make_tier_stall_filter_fn(owner_id, min_stall_tier, entity_id))
         rating_fn = _make_stall_rating_fn(entity_id, _make_tier_stall_rating_fn(math.max(1, min_stall_tier)))
      end

      ai:set_think_output({
         filter_fn = filter_fn,
         rating_fn = rating_fn,
         owner_player_id = owner_id,
      })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(WorkAtStall)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(1).filter_fn,
            rating_fn = ai.BACK(1).rating_fn,
            description = 'finding market stall entities',
            owner_player_id = ai.BACK(1).owner_player_id
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(2).filter_fn,
            item = ai.BACK(1).item
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = stonehearth_ace.mercantile,
            event = 'stonehearth_ace:merchants:depart_time',
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(3).item
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(4).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth_ace:merchant:work', {
            stall = ai.BACK(6).item
         })
