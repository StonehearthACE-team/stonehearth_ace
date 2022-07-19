local WorkByHearth = class()

WorkByHearth.name = 'work by hearth'
WorkByHearth.does = 'stonehearth_ace:merchant:work_by_hearth'
WorkByHearth.args = {}
WorkByHearth.priority = 1

local function _make_filter_fn(owner_id, town)
   return function(item)
         if owner_id ~= '' and radiant.entities.get_player_id(item) ~= owner_id then
            return false
         end
         return item == town:get_hearth() or item == town:get_banner()
      end
end

function WorkByHearth:start_thinking(ai, entity, args)
   -- find an appropriate stall to work at
   -- if we need a specific uri stall, go for that
   -- if we need a specific tier, try to find one at least that tier, preferring the lowest possible
   -- require a stall to either be unoccupied or set to this merchant already
   local merchant_component = entity:get_component('stonehearth_ace:merchant')
   if merchant_component and not merchant_component:should_depart() then
      local owner_id = merchant_component:get_player_id()
      local town = stonehearth.town:get_town(owner_id)
      if town then
         local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:merchant:work_by_hearth', owner_id, _make_filter_fn(owner_id, town))
         ai:set_think_output({
            filter_fn = filter_fn,
            owner_player_id = owner_id,
         })
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(WorkByHearth)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(1).filter_fn,
            description = 'finding a town hearth or banner',
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
            path = ai.PREV.path,
            stop_distance = 8,
         })
         :execute('stonehearth_ace:merchant:work', {})
