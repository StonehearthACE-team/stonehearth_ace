local animal_filters = {}

function animal_filters.make_available_pet_bed_filter(entity)
   local player_id = entity:get_player_id()
   local animal_data = radiant.entities.get_entity_data(entity, 'stonehearth:pasture_animal')
   local animal_size = animal_data and animal_data.size
   local key = player_id .. '|' .. (animal_size or '')

   return stonehearth.ai:filter_from_key('stonehearth_ace:pasture_animal:sleep_in_bed', key, function(target)
      if target:get_player_id() ~= player_id then
         return false
      end
      
      local bed_data = radiant.entities.get_entity_data(target, 'stonehearth_ace:pasture_bed')
      if bed_data then
         -- check if the bed size is the same as the animal size
         if not animal_size or animal_size == bed_data.size then
            return true
         end
      end

      return false
   end)
end

return animal_filters
