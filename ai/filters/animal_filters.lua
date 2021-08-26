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
         -- if it's a pasture bed in a pasture, make sure the animal belongs to the same pasture
         -- EDIT: not doing this because it would require including the pasture id in the filter key and making/updating different filters
         -- maybe it would be worth it to have a separate filter per pasture though? only a few pastures per player
         -- local pasture_item = target:get_component('stonehearth_ace:pasture_item')
         -- if pasture_item then
         --    local equipment_component = entity:get_component('stonehearth:equipment')
         --    local pasture_tag = equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag')
         --    local shepherded_animal_component = pasture_tag and pasture_tag:get_component('stonehearth:shepherded_animal')
         --    if not shepherded_animal_component or shepherded_animal_component:get_pasture() ~= pasture_item:get_pasture() then
         --       return false
         --    end
         -- end

         -- check if the bed size is the same as the animal size
         if not animal_size or animal_size == bed_data.size then
            -- make sure it's not currently being targeted for a task
            local task_tracker = target:get_component('stonehearth:task_tracker')
            if task_tracker and task_tracker:get_task_player_id() == player_id then
               return false
            end
            return true
         end
      end

      return false
   end)
end

return animal_filters
