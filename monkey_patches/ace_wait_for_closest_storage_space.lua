local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3

local AceWaitForClosestStorageSpace = radiant.class()
local log = radiant.log.create_logger('wait_for_closest_storage_space')

function AceWaitForClosestStorageSpace:start_thinking(ai, entity, args)
   self._ai = ai

   local num_checked = 0
   local check_storage = function(storage_entity)
         num_checked = num_checked + 1   
         local storage_component = storage_entity:get_component('stonehearth:storage')
         return storage_component and storage_component:is_public() and not storage_component:is_full() and storage_component:passes(args.item) and storage_component
      end

   local priority_distance = stonehearth.constants.inventory.CRAFTER_PRIORITY_STORAGE_RADIUS
   local checked_storage = {}

   -- do a very nearby check of storage entities to prioritize
   local location = radiant.entities.get_world_grid_location(entity)
   local cube = Cube3(location):inflated(Point3(priority_distance, 1, priority_distance))
   local nearby_entities = radiant.terrain.get_entities_in_cube(cube)
   for id, nearby_entity in pairs(nearby_entities) do
      if check_storage(nearby_entity) then
         log:debug('%s found priority storage %s after %s entities checked', entity, nearby_entity, num_checked)
         self._ai:set_think_output({
            storage = nearby_entity
         })
         return
      end
      checked_storage[id] = true
   end


   local shortest_distance
   local closest_storage
   local short_circuit_distance = stonehearth.constants.inventory.MAX_INSIGNIFICANT_PATH_LENGTH
   local storage = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))
                                                :get_all_public_storage()

   --Iterate through the stockpiles. If we match the stockpile criteria AND there is room
   --check if the stockpile is the closest such stockpile to the entity
   for id, storage_entity in pairs(storage) do
      if not checked_storage[id] then
         local storage_component = check_storage(storage_entity)
         if storage_component then
            local distance_between = radiant.entities.distance_between(entity, storage_entity)
            
            -- HACK: This action is only used for crafter output, so prefer output crates.
            if storage_component:get_type() == 'output_crate' then
               distance_between = distance_between / 2
            end

            if not closest_storage or distance_between < shortest_distance then
               closest_storage = storage_entity
               shortest_distance = distance_between
               
               -- ACE: add short-circuit if it's a very short distance
               if shortest_distance <= short_circuit_distance then
                  break
               end
            end
         end
      end
   end

   --If there is a closest storage, return it
   if closest_storage then
      log:debug('%s settled for storage %s after %s checked entities', entity, closest_storage, num_checked)
      self._ai:set_think_output({
         storage = closest_storage
      })
   else
      log:debug('%s couldn\'t find storage for %s! checked %s entities', entity, args.item, num_checked)
   end
end

return AceWaitForClosestStorageSpace