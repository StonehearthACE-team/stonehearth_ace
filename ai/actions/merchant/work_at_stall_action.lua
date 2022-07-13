local WorkAtStall = class()

WorkAtStall.name = 'work at stall'
WorkAtStall.does = 'stonehearth_ace:merchant:work_at_stall'
WorkAtStall.args = {}
WorkAtStall.priority = 1

local function _make_tier_stall_filter_fn(owner_id, min_tier)
   return function(item)
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         local stall_data = radiant.entities.get_component_data(item, 'stonehearth_ace:market_stall')
         return stall_data and stall_data.tier and stall_data.tier >= min_tier
      end
end

local function _make_unique_stall_filter_fn(owner_id, uri)
   return function(item)
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         return item:get_uri() == uri
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
      local required_stall = merchant_component:get_required_stall()
      if required_stall then
         filter_fn = stonehearth.ai:filter_from_key(
               'stonehearth_ace:merchant:work_at_stall',
               owner_id .. '|' .. required_stall,
               _make_unique_stall_filter_fn(owner_id, required_stall))
      else
         local min_stall_tier = merchant_component:get_stall_tier()
         filter_fn = stonehearth.ai:filter_from_key(
               'stonehearth_ace:merchant:work_at_stall',
               owner_id .. '|' .. tostring(min_stall_tier),
               _make_tier_stall_filter_fn(owner_id, min_stall_tier))
         rating_fn = _make_tier_stall_rating_fn(math.max(1, min_stall_tier))
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
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).item
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth_ace:merchant:work', {
            stall = ai.BACK(5).item
         })
