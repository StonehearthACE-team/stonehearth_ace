-- ACE: add ignore_leases handling for entities within the storage (no point deciding on a storage if we can't lease any of its items)

local Path = _radiant.sim.Path
local Entity = _radiant.om.Entity

local FindReachableStorageContainingBestEntityType = radiant.class()

FindReachableStorageContainingBestEntityType.name = 'find reachable storage containing best entity type'
FindReachableStorageContainingBestEntityType.does = 'stonehearth:find_reachable_storage_containing_best_entity_type'
FindReachableStorageContainingBestEntityType.args = {
   filter_fn = 'function',      -- a filter for the items to find
   rating_fn = 'function',      -- a rating function that returns a score 0-1 given the item and entity
   description = 'string',      -- description of the initiating compound task (for debugging).
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   ignore_workbenches = {
      type = 'boolean',
      default = true,
   },
   
}
FindReachableStorageContainingBestEntityType.think_output = {
   storage = Entity,            -- the found storage (container)
}
FindReachableStorageContainingBestEntityType.priority = {0, 1}

local log = radiant.log.create_logger('find_reachable_storage_containing_best_entity_type')

-- TODO: Reuse the copy of this in find_path_to_storage_containing_entity_type.
local function make_storage_filter_fn(entity, args_filter_fn, owner_player_id, ignore_workbenches)
   return function(storage)
         local storage_comp = storage:get_component('stonehearth:storage')
         if not storage_comp then
            return false
         end

         -- Don't look in stockpiles.  It's expensive and they can be found by the
         -- generic 'stonehearth:find_path_to_entity_type' which just looks for stuff
         -- on the ground.
         if storage:get_component('stonehearth:stockpile') then
            return false
         end

         -- don't look in workbenches normally (restocking is an exception)
         if ignore_workbenches and storage:get_component('stonehearth:workshop') then
            return false
         end

         -- Don't take items out of non-public storage (e.g.hearthling backpacks)
         if not storage_comp:is_public() then
            return false
         end

         -- cache these upvalues for the loop
         local ai_service = stonehearth.ai
         for _, item in pairs(storage_comp:get_items()) do
            if ai_service:fast_call_filter_fn(args_filter_fn, item) then
               return true
               -- !!! can't do lease checking because the hearthling entity isn't part of the filter_fn key
               -- !!! so multiple entities use the same filter_fn and get conflicting results on the lease
               -- if ignore_leases or stonehearth.ai:can_acquire_ai_lease(item, entity, owner_player_id) then
               --    return true
               -- else
               --    log:debug('%s can\'t acquire lease on %s matching filter_fn %s', entity, item, args_filter_fn)
               -- end
            end
         end

         return false
      end
end

local function make_storage_rating_fn(item_filter_fn, item_rating_fn)
   if item_rating_fn then
      return function(storage_entity, entity)
            local storage = storage_entity:get_component('stonehearth:storage')
            local storage_location = radiant.entities.get_world_grid_location(storage_entity)

            local best_rating = 0
            for _, item in pairs(storage:get_items()) do
               if item_filter_fn(item) then
                  local rating = item_rating_fn(item, entity, nil, storage_location)  -- HACK: 3rd/4th args only used by InventoryService.rate_item().
                  if rating > best_rating then
                     best_rating = rating
                     if rating == 1 then
                        break
                     end
                  end
               end
            end

            return best_rating
         end
   else
      return function()
         return 1
      end
   end
end

function FindReachableStorageContainingBestEntityType:start_thinking(ai, entity, args)
   local key = tostring(args.filter_fn) .. tostring(args.ignore_workbenches)
   local storage_filter_fn = stonehearth.ai:filter_from_key('stonehearth:find_reachable_storage_containing_best_entity_type', key,
                                                            make_storage_filter_fn(entity, args.filter_fn, args.owner_player_id, args.ignore_workbenches))
   ai:set_think_output({
      storage_filter_fn = storage_filter_fn,
      storage_rating_fn = make_storage_rating_fn(args.filter_fn, args.rating_fn),
   })
end

function FindReachableStorageContainingBestEntityType:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:find_best_reachable_entity_by_type')
end

local ai = stonehearth.ai
return ai:create_compound_action(FindReachableStorageContainingBestEntityType)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.storage_filter_fn,
            rating_fn = ai.PREV.storage_rating_fn,
            description = ai.ARGS.description,
            owner_player_id = ai.ARGS.owner_player_id,
         })
         :set_think_output({
            storage = ai.PREV.item,
         })