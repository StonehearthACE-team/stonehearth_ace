local shared_filters = require 'ai.filters.shared_filters'
local PetSleepInBed = radiant.class()

PetSleepInBed.name = 'sleep in pet bed'
PetSleepInBed.does = 'stonehearth_ace:pet_sleep_in_bed'
PetSleepInBed.args = {}
PetSleepInBed.priority = 0.9

local function _available_pet_bed_filter(entity)
   local player_id = entity:get_player_id()

   return stonehearth.ai:filter_from_key('stonehearth_ace:pet:sleep_in_bed', player_id, function(target)
      if target:get_player_id() ~= player_id then
         return false
      end
      if radiant.entities.get_entity_data(target, 'stonehearth_ace:pet_bed') then
         return true
      end
      return false
   end)
end

local function _pet_bed_rating_filter(entity)
   local owner_bed_location = nil
   local pet_component = entity:get_component('stonehearth:pet')
   if pet_component then
      local pet_owner = entity:get_component('stonehearth:pet'):get_owner()

      local object_owner_component = pet_owner and pet_owner:is_valid() and pet_owner:get_component('stonehearth:object_owner')
      local bed = object_owner_component and object_owner_component:get_owned_object('bed')
      if bed and bed:is_valid() then
         owner_bed_location = radiant.entities.get_world_grid_location(bed)
      end
   end
   return function(bed)
      local bed_location = radiant.entities.get_world_grid_location(bed)
      if owner_bed_location then
         return -owner_bed_location:distance_to_squared(bed_location)
      end
      local entity_location = radiant.entities.get_world_grid_location(entity)
      return -entity_location:distance_to_squared(bed_location)
   end
end


local ai = stonehearth.ai
return ai:create_compound_action(PetSleepInBed)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.CALL(_available_pet_bed_filter, ai.ENTITY),
            rating_fn = ai.CALL(_pet_bed_rating_filter, ai.ENTITY),
            description = 'find best pet bed',
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(3).item })
         :execute('stonehearth_ace:pet_sleep_in_bed_adjacent', { bed = ai.BACK(4).item })
