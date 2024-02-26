local AcePickupItemFromStorageAdjacent = class()

function AcePickupItemFromStorageAdjacent:run(ai, entity, args)
   local storage = args.storage
   local item = args.item
   radiant.check.is_entity(item)

   local parent = radiant.entities.get_parent(item)
   local use_container = not parent or parent == storage
   local pickup_target = use_container and storage or item

   if not radiant.entities.is_adjacent_to(entity, pickup_target) then
      ai:abort(string.format('%s is not adjacent to %s', tostring(entity), tostring(pickup_target)))
   end

   if stonehearth.ai:prepare_to_pickup_item(ai, entity, item, args.owner_player_id) then
      return
   end
   assert(not radiant.entities.get_carrying(entity))

   local item_location = radiant.entities.get_world_location(item)
   if item_location then
      -- stockpiles
      radiant.entities.turn_to_face(entity, item)
   else
      -- crates
      radiant.entities.turn_to_face(entity, storage)
   end

   -- ACE: if the storage entity has a specific effect to run, do that
   local storage_open_effect, user_open_effect = self._storage_component:get_storage_open_effects()
   if storage_open_effect then
      radiant.effects.run_effect(storage, storage_open_effect)

      if user_open_effect then
         ai:execute('stonehearth:run_effect', { effect = user_open_effect })
      end
   end

   local success = self._storage_component:remove_item(args.item:get_id())
   if not success then
      ai:abort('item not found in storage')
   end

   local storage_location = radiant.entities.get_world_grid_location(storage)
   stonehearth.ai:pickup_item(ai, entity, args.item, nil, args.owner_player_id)

   ai:execute('stonehearth:run_pickup_effect', { location = storage_location })
end

return AcePickupItemFromStorageAdjacent
