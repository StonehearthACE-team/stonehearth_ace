local Entity = _radiant.om.Entity
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local PickupItemWithUri = radiant.class()

PickupItemWithUri.name = 'pickup item with uri'
PickupItemWithUri.does = 'stonehearth:pickup_item_with_uri'
PickupItemWithUri.args = {
   uri = 'string',      -- uri we want
   min_stacks = {
      type = 'number',
      default = 0
   },
   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
PickupItemWithUri.think_output = {
   item = Entity,            -- what was actually picked up
}
PickupItemWithUri.priority = 0

function PickupItemWithUri:start_thinking(ai, entity, args)
   local uri = args.uri
   local player_id = radiant.entities.get_player_id(entity)
   local is_owned_by_another_player = radiant.entities.is_owned_by_another_player
   local key = player_id .. ':' .. uri
   local min_stacks = args.min_stacks > 0 and args.min_stacks
   if min_stacks then
      key = key .. ':' .. min_stacks
   end
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:pickup_item_with_uri', key, function (entity)
         if is_owned_by_another_player(entity, player_id) then
            -- player does not own this item
            return false
         end

         -- if we specified min_stacks and this entity doesn't have at least that many, no good
         if min_stacks then
            local stacks_component = entity:get_component('stonehearth:stacks')
            if not stacks_component or stacks_component:get_stacks() < min_stacks then
               return false
            end
         end

         local root, iconic = entity_forms_lib.get_forms(entity)
         if root and iconic then
            -- if this is an object with entity forms

            -- if we found the iconic forms item, we can check for if it matches
            -- DO NOT pick up items that are the root. Otherwise we will
            -- try to undeploy items that the user has specifically placed!
            if entity == iconic then
               -- if we are specifically looking for the iconic uri, then we're good
               if entity:get_uri() == uri then
                  return true
               end

               -- else if we are looking for the root's uri and it matches, then good.
               if root:get_uri() == uri then
                  return true
               end
            end
         elseif entity:get_uri() == uri then
            return true
         end
         return false
      end)

   ai:set_think_output({
         filter_fn = filter_fn,
         description = uri
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupItemWithUri)
         :execute('stonehearth:pickup_item_type', {
            filter_fn = ai.PREV.filter_fn,
            description = ai.PREV.description,
            rating_fn = ai.ARGS.rating_fn
         })
         :set_think_output({ item = ai.PREV.item })
