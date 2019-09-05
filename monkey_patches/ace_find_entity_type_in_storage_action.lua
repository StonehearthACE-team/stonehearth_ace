local AceFindEntityTypeInStorageAction = class()

-- ACE: have to override this whole thing to set the utility based on the rating
function AceFindEntityTypeInStorageAction:start_thinking(ai, entity, args)
   -- Look for _anything_ in the storage that passes our filter, and can be acquired,
   -- optionally preferring things that are rated higher by the rating function.
   local storage = args.storage:get_component('stonehearth:storage')
   if not storage then
      ai:set_debug_progress('dead: argument has no storage')
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
         ai:set_utility(best_rating)
      else
         ai:set_debug_progress('selecting ' .. tostring(best_item))
         ai:set_utility(1)
      end
      
      ai:set_think_output({ item = best_item })
   else
      ai:set_debug_progress('dead: no reservable matching items')
   end
end

return AceFindEntityTypeInStorageAction
