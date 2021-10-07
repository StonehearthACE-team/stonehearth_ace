local ClearItem = radiant.class()

ClearItem.name = 'clear item'
ClearItem.does = 'stonehearth:clear_item'
ClearItem.args = {}
ClearItem.priority = 0

local function _clear_item_fn(player_id, item)
   if not item or not item:is_valid() then
      return false
   end

   -- ACE: check if an interaction proxy is in play
   local interaction_proxy_component = item:get_component('stonehearth_ace:interaction_proxy')
   if interaction_proxy_component then
      item = interaction_proxy_component:get_entity() or item
   end

   local task_tracker_component = item:get_component('stonehearth:task_tracker')
   if not task_tracker_component then
      return false
   end

   return task_tracker_component:is_task_requested(player_id, nil, ClearItem.does)
end

function ClearItem:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:clear_item', work_player_id, function(item)
         return _clear_item_fn(work_player_id, item)
      end)

   -- TODO: do we really want this check?
   if not ai.CURRENT.carrying then
      ai:set_think_output({
         clear_filter_fn = filter_fn,
         owner_player_id = work_player_id,
      })
   end
end

local function _get_actual_entity(item)
   local interaction_proxy_component = item:get_component('stonehearth_ace:interaction_proxy')
   if interaction_proxy_component then
      item = interaction_proxy_component:get_entity() or item
   end

   return item
end

local ai = stonehearth.ai
return ai:create_compound_action(ClearItem)
   :execute('stonehearth:drop_carrying_now', {})
   :execute('stonehearth:abort_on_event_triggered', {
      source = ai.ENTITY,
      event_name = 'stonehearth:work_order:haul:work_player_id_changed',
   })
   :execute('stonehearth:find_path_to_entity_type', {
      filter_fn = ai.BACK(3).clear_filter_fn,
      description = 'finding clearable items',
      owner_player_id = ai.BACK(3).owner_player_id,
   })
   :execute('stonehearth:abort_on_reconsider_rejected', {
      filter_fn = ai.BACK(4).clear_filter_fn,
      item = ai.BACK(1).destination,
   })
   :execute('stonehearth:reserve_entity', {
      entity = ai.CALL(_get_actual_entity, ai.BACK(2).destination),
      owner_player_id = ai.BACK(5).owner_player_id,
   })
   :execute('stonehearth:goto_entity', {
      entity = ai.BACK(3).destination,
   })
   :execute('stonehearth:clear_item_adjacent', {
      item = ai.BACK(2).entity,
      owner_player_id = ai.BACK(7).owner_player_id,
   })
