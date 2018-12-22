local Entity = _radiant.om.Entity

local PetPullItemFromStorageAdjacent = radiant.class()
PetPullItemFromStorageAdjacent.name = 'pet pull item from storage adjacent'
PetPullItemFromStorageAdjacent.does = 'stonehearth_ace:pet_pull_item_from_storage_adjacent'
PetPullItemFromStorageAdjacent.args = {
   item = Entity,
   storage = Entity,
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
PetPullItemFromStorageAdjacent.priority = 0

function PetPullItemFromStorageAdjacent:start_thinking(ai, entity, args)
   self._storage_component = args.storage:get_component('stonehearth:storage')

   if self._storage_component and self._storage_component:contains_item(args.item:get_id()) then
      ai:set_think_output()
   end
end

function PetPullItemFromStorageAdjacent:run(ai, entity, args)
   local storage = args.storage
   local item = args.item
   radiant.check.is_entity(item)

   local parent = radiant.entities.get_parent(item)
   local use_container = not parent or parent == storage
   local pickup_target = use_container and storage or item

   if not radiant.entities.is_adjacent_to(entity, pickup_target) then
      ai:abort(string.format('%s is not adjacent to %s', tostring(entity), tostring(pickup_target)))
   end

   local item_location = radiant.entities.get_world_location(item)
   if item_location then
      -- stockpiles
      radiant.entities.turn_to_face(entity, item)
   else
      -- crates
      radiant.entities.turn_to_face(entity, storage)
   end

   local success = self._storage_component:remove_item(args.item:get_id())
   if not success then
      ai:abort('item not found in storage')
   end

   local storage_location = radiant.entities.get_world_grid_location(storage)
   -- TODO add in pet pull item effect here
   -- stonehearth.ai:pickup_item(ai, entity, args.item, nil, args.owner_player_id)
   -- ai:execute('stonehearth:run_pickup_effect', { location = storage_location })

   local location = radiant.entities.get_world_grid_location(entity)
   radiant.terrain.place_entity(item, location)
end

return PetPullItemFromStorageAdjacent
