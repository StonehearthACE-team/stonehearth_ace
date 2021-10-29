local Entity = _radiant.om.Entity
local PickupItemType = radiant.class()

PickupItemType.name = 'pickup item type'
PickupItemType.does = 'stonehearth:pickup_item_type'
PickupItemType.args = {
   filter_fn = 'function',
   rating_fn = {
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',
   from_backpack = {
      type = 'boolean',
      default = true,
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
PickupItemType.think_output = {
   item = Entity,          -- what actually got picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
PickupItemType.priority = {0, 1}

function PickupItemType:start_thinking(ai, entity, args)
   if not ai.CURRENT.carrying then
      ai:set_think_output({
            description = 'pickup ' .. args.description .. ' (ground)'
         })
   end
end

function PickupItemType:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type') * 0.8
        + child_utilities:get('stonehearth:follow_path') * 0.2
end

local function _get_actual_entity(item)
   local interaction_proxy_component = item:get_component('stonehearth_ace:interaction_proxy')
   if interaction_proxy_component then
      item = interaction_proxy_component:get_entity() or item
   end

   return item
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupItemType)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.ARGS.filter_fn,
            rating_fn = ai.ARGS.rating_fn,
            description = ai.PREV.description,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity', {
            entity = ai.CALL(_get_actual_entity, ai.BACK(2).path:get_destination()),
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth:pickup_item_adjacent', {
            item = ai.PREV.entity,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.BACK(4).path:get_path_length()
         })
