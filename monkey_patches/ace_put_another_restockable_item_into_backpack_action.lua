local Entity = _radiant.om.Entity

local PutAnotherRestockableItemIntoBackpack = require 'stonehearth.ai.actions.put_another_restockable_item_into_backpack_action'
local AcePutAnotherRestockableItemIntoBackpack = radiant.class()
--AcePutAnotherRestockableItemIntoBackpack.ACE_USE_MERGE_INTO_TABLE = true

PutAnotherRestockableItemIntoBackpack.args.filter_fn = {            -- an optional filter function to limit what gets picked up
      type = 'function',
      default = stonehearth.ai.NIL,
   }

local function _should_restock(item)
   local entity_forms_component = item:get_component('stonehearth:entity_forms')
   if entity_forms_component and not entity_forms_component:get_should_restock() then
      return false
   end
   return true
end

-- ACE: only pick up the item if it should be restocked
function AcePutAnotherRestockableItemIntoBackpack:run(ai, entity, args)
   if radiant.entities.get_carrying(entity) then
      -- we didn't check ai.CURRENT.carrying before entering here, so we
      -- may need to clear what we've got to pick up something else
      ai:execute('stonehearth:clear_carrying_now', { owner_player_id = args.owner_player_id })
   end

   if self._path then
      if radiant.entities.exists(self._item) then
         -- Only follow path if item is valid.
         -- It is possible for the item to become invalid between thinking and start
         -- However, we want to keep going with the loop so we can finish restocking the other times we picked up.
         ai:execute('stonehearth:follow_path', { path = self._path })
         if _should_restock(self._item) then
            local storage = stonehearth.inventory:get_inventory(entity:get_player_id()):container_for(self._item)
            if storage then
               ai:execute('stonehearth:pickup_item_from_storage_adjacent', {
                  storage = storage,
                  item = self._item,
                  owner_player_id = args.owner_player_id,
               })
            else
               ai:execute('stonehearth:pickup_item_adjacent', {
                  item = self._item,
                  owner_player_id = args.owner_player_id,
                  is_restocking = true,
               })
            end

            -- Perform the same checks as put_carrying_in_backpack does before calling it,
            -- as otherwise it fails its think and blows up the AI state.
            local carrying = radiant.entities.get_carrying(entity)
            if (radiant.entities.exists(entity)
                  and not entity:get_component('stonehearth:storage'):is_full()
                  and carrying
                  and stonehearth.catalog:is_item(carrying:get_uri())) then
               ai:execute('stonehearth:put_carrying_in_backpack', {
                  owner_player_id = args.owner_player_id,
               })
            end
         end
      end
   end
end

function AcePutAnotherRestockableItemIntoBackpack:_find_path_to_item(ai, entity, args)
   if not ai.CURRENT.storage then
      self._log:debug('have no backpack')
      ai:set_debug_progress('have no backpack')
      return
   end

   if ai.CURRENT.storage.full then
      self._log:debug('backpack full')
      ai:set_debug_progress('backpack full')
      return
   end
   
   local storage = args.storage:get_component('stonehearth:storage')
   if args.reserve_space and not storage:can_reserve_space() then  -- we'll reserve properly later, but if we know it won't work, don't waste time pathing
      ai:set_debug_progress('target storage full')
      return
   end

   -- find all the items nearby and see if we can find a path to them
   local pathfinder = entity:add_component('stonehearth:pathfinder')
                                 :get_sync_pathfinder()
                                 :set_source(ai.CURRENT.location)

   local function ok_to_pickup(item)
      if not stonehearth.ai:can_acquire_ai_lease(item, entity, args.owner_player_id) then
         self._log:debug('could not lease %s', item)
         return false
      end
      if ai.CURRENT.self_reserved[item:get_id()] then
         self._log:debug('%s is self reserved already.', item)
         return false
      end

      -- if it has entity_forms and is not set as should_restock, cancel
      if not _should_restock(item) then
         return false
      end

      -- ACE: check filter if provided
      if args.filter_fn then
         return args.filter_fn(item)
      end

      return true
   end
   
   local count = 0
   local candidate_scores = {}
   local container_to_item = {}
   local interaction_proxy_to_item = {}
   local inventory = stonehearth.inventory:get_inventory(entity:get_player_id())
   for _, entry in ipairs(args.candidates) do
      -- TODO: Stop supporting these fallbacks.
      local item = entry.entity or entry
      if ok_to_pickup(item) then
         if radiant.entities.exists_in_world(item) then
            self._log:debug('adding %s to pathfinder', item)
            -- ACE: if it has an interaction proxy, use that instead
            local use_item = item
            local entity_forms_component = item:get_component('stonehearth:entity_forms')
            if entity_forms_component then
               local interaction_proxy = entity_forms_component:get_interaction_proxy()
               if interaction_proxy then
                  interaction_proxy_to_item[interaction_proxy:get_id()] = item
                  use_item = interaction_proxy
               end
            end

            pathfinder:add_destination(use_item)
            count = count + 1
         else
            local container = inventory:container_for(item)
            self._log:debug('adding %s to pathfinder', container)
            if container and radiant.entities.exists_in_world(container) then  -- Could be in someone's backpack now.
               pathfinder:add_destination(container)
               container_to_item[container:get_id()] = item  -- this may overwrite; that's ok.
               count = count + 1
            end
         end
         candidate_scores[item:get_id()] = entry.score or 0
         if count >= 4 then
            self._log:debug('got enough.  ignoring remaining items')
            break
         end
      end
   end

   -- allow somewhat twisty paths...
   pathfinder:start()
   local path = pathfinder:search_until_travelled(args.range)
   pathfinder:stop()
   pathfinder:reset()

   if not path then
      self._log:debug('no path')
      ai:set_debug_progress('no path')
      return
   end
   
   if args.reserve_space then
      self._space_lease = args.storage:get_component('stonehearth:storage'):reserve_space(entity, 'another item think')
      if not self._space_lease then
         ai:set_debug_progress('target storage full')
         return
      end
      self._space_lease_expiry_timer = radiant.set_realtime_timer('temp space lease expiry', 1000, function()
            if self._space_lease then
               self._space_lease:destroy()
               self._space_lease = nil
            end
         end)
   end

   self._log:debug('woot! %s', path:get_destination())
   -- woot!  we found a path to one of them.  update the future state of
   -- the entity and remember we need to follow this path later on.
   self._path = path

   self._item = path:get_destination()
   if container_to_item[self._item:get_id()] then
      self._item = container_to_item[self._item:get_id()]
   elseif interaction_proxy_to_item[self._item:get_id()] then
      self._item = interaction_proxy_to_item[self._item:get_id()]
   end
   ai.CURRENT.location = path:get_finish_point()
   
   -- if we want to be able to remove the item from our backpack later, it needs to be the actual item
   -- i.e., if it has entity forms, then it will put the iconic into the backpack, not the root
   local backpack_item = self._item
   local entity_forms_component = self._item:get_component('stonehearth:entity_forms')
   if entity_forms_component then
      backpack_item = entity_forms_component:get_iconic_entity() or backpack_item
   end
   ai.CURRENT.storage:add_item(backpack_item)

   ai.CURRENT.self_reserved[self._item:get_id()] = self._item
   self._lease = stonehearth.ai:acquire_ai_lease(self._item, entity, 1000, args.owner_player_id)
   self._item_score = candidate_scores[self._item:get_id()]
   ai:set_debug_progress(string.format('temp-reserved %s; rating = %s', tostring(self._item), self._item_score))
end

return AcePutAnotherRestockableItemIntoBackpack
