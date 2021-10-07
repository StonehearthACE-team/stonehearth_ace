local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local Entity = _radiant.om.Entity
local PickupItem = radiant.class()

PickupItem.name = 'pickup an item'
PickupItem.does = 'stonehearth:pickup_item'
PickupItem.args = {
   item = Entity,
   relative_orientation = {
      type = 'number',
      default = stonehearth.ai.NIL,
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   is_restocking = {
      type = 'boolean',
      default = false,
   }
}
PickupItem.priority = 0.0

function PickupItem:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying then
      ai:set_debug_progress('dead: already carrying')
      return
   end
   
   local item = args.item

   -- if we're instructed to pick up the root form of an item,
   -- but the item is currently in iconic form, just go right for
   -- the icon.  picking it up would have convereted it to an icon anyway
   local root, iconic = entity_forms_lib.get_forms(args.item)
   if root and iconic then
      local root_parent = root:add_component('mob'):get_parent()
      if not root_parent then
         local iconic_parent = iconic:add_component('mob'):get_parent()
         if iconic_parent then
            item = iconic
         end
      end
   end

   ai:set_think_output({
         item = item
      })
end

local function _get_interaction_entity(entity)
   local entity_forms = entity:get_component('stonehearth:entity_forms')
   return entity_forms and entity_forms:get_interaction_proxy() or entity
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupItem)
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(1).item,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :execute('stonehearth:goto_entity', {
            entity = ai.CALL(_get_interaction_entity, ai.BACK(2).item)
         })
         :execute('stonehearth:pickup_item_adjacent', {
            item = ai.BACK(3).item,
            relative_orientation = ai.ARGS.relative_orientation,
            owner_player_id = ai.ARGS.owner_player_id,
            is_restocking = ai.ARGS.is_restocking,
         })
