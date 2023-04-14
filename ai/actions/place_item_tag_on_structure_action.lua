local PlaceItemOnStructure = radiant.class()

PlaceItemOnStructure.name = 'place an item with tag'
PlaceItemOnStructure.does = 'stonehearth_ace:place_item_tag_on_structure'
PlaceItemOnStructure.args = {
   placement_tag = 'string',
}
PlaceItemOnStructure.priority = 0

local function _make_filter_fn(player_id, required_placement_tag)
   return function(item)
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
      if not task_tracker_component:is_task_requested(player_id, nil, 'place_item_on_structure') then
         return false
      end

      local placement_tag
      local iconic_component = item:get_component('stonehearth:iconic_form')
      if iconic_component then
         item = iconic_component:get_root_entity()
      end
      local placement_data = radiant.entities.get_entity_data(item, 'stonehearth:placement')
      if placement_data and placement_data.tag then
         placement_tag = placement_data.tag
      end

      return placement_tag == required_placement_tag
   end
end

function PlaceItemOnStructure:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local filter_key = work_player_id .. ':' .. args.placement_tag
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:place_item_on_structure', filter_key, _make_filter_fn(work_player_id, args.placement_tag))

   ai:set_think_output({
      filter_fn = filter_fn,
      owner_player_id = work_player_id,
   })
end

function PlaceItemOnStructure:start(ai, entity, args)
   ai:set_status_text_key('stonehearth:ai.actions.status_text.place_item_on_structure', { target = ai.CURRENT.carrying })
end

local function _get_actual_entity(item)
   local interaction_proxy_component = item:get_component('stonehearth_ace:interaction_proxy')
   if interaction_proxy_component then
      item = interaction_proxy_component:get_entity() or item
   end

   return item
end

local ai = stonehearth.ai
return ai:create_compound_action(PlaceItemOnStructure)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:pickup_item_type', {
               filter_fn = ai.BACK(2).filter_fn,
               description = 'item needing placing',
               owner_player_id = ai.BACK(2).owner_player_id,
             })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(3).filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:get_placement_ghost_for_item', {
               item = ai.CALL(_get_actual_entity, ai.BACK(2).item),
            })
         :execute('stonehearth:goto_entity', {
               entity = ai.BACK(1).ghost,
            })
         :execute('stonehearth:place_carrying_on_structure_adjacent', {
               ghost = ai.BACK(2).ghost,
            })
