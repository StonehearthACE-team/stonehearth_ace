local Entity = _radiant.om.Entity

local FindEntityTypeInStorageAction = radiant.class()

FindEntityTypeInStorageAction.name = 'find entity type in storage'
FindEntityTypeInStorageAction.does = 'stonehearth:find_entity_type_in_storage'
FindEntityTypeInStorageAction.args = {
   filter_fn = 'function',
   rating_fn = {              -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   storage = Entity,          -- storage which potentially has the item
   ignore_reserved_from_self = {
      type = 'boolean',
      default = true,
   },
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
FindEntityTypeInStorageAction.think_output = {
   item = Entity,             -- the item found
}
FindEntityTypeInStorageAction.priority = {0, 1}  -- Quality if rating_fn specified; 0 otherwise

function FindEntityTypeInStorageAction:start_thinking(ai, entity, args)
   -- Look for _anything_ in the storage that passes our filter, and can be acquired,
   -- optionally preferring things that are rated higher by the rating function.
   local storage = args.storage:get_component('stonehearth:storage')
   if not storage then
      ai:set_debug_progress('dead: argument doesn has no storage')
      return
   end
   
   local best_rating = -1
   local best_item = nil
   for _, item in pairs(storage:get_items()) do
      if item and item:is_valid() then
         local reserved = false
         if args.ignore_reserved_from_self then
            reserved = ai.CURRENT.self_reserved[item:get_id()] ~= nil
         end
         
         local storage_location = radiant.entities.get_world_grid_location(args.storage)
         if not reserved and args.filter_fn(item) then
            if stonehearth.ai:can_acquire_ai_lease(item, entity, args.owner_player_id) then
               if args.rating_fn then
                  local rating = args.rating_fn(item, entity, nil, storage_location)  -- HACK: 3rd/4th args only used by InventoryService.rate_item().
                  if rating > best_rating then
                     best_rating = rating
                     best_item = item
                     if rating == 1 then
                        break
                     end
                  end
               else
                  best_item = item
                  break
               end
            end
         end
      end
   end

   if best_item then
      if best_rating ~= -1 then
         ai:set_debug_progress('selecting ' .. tostring(best_item) .. '; rating = ' .. tostring(best_rating))
      else
         ai:set_debug_progress('selecting ' .. tostring(best_item))
      end
      ai:set_utility(math.max(0, best_rating))
      ai:set_think_output({ item = best_item })
   else
      ai:set_debug_progress('dead: no reservable matching items')
   end
end

return FindEntityTypeInStorageAction
