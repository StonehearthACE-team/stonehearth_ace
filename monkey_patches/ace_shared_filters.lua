local ace_shared_filters = {}

-- this is only used for people sleeping or being rescued to a bed
-- we already have a separate priority care filter/action that covers those beds, so we don't need to include unownable beds here
function ace_shared_filters.make_is_unowned_available_bed_filter(entity)
   local player_id = entity:get_player_id()

   return stonehearth.ai:filter_from_key('stonehearth:sleep:sleep_in_unowned_bed', player_id, function(target)
         if target:get_player_id() ~= player_id then
            return false
         end

         if radiant.entities.get_entity_data(target, 'stonehearth:bed') then
            local ownable_component = target:get_component('stonehearth:ownable_object')
            -- ACE: added check for ownable component not being there
         	if ownable_component and ownable_component:get_owner() == nil and not target:add_component('stonehearth:mount'):is_in_use() then
               return true
            end
         end
         return false
      end)
end

function ace_shared_filters.make_is_priority_care_available_bed_filter(entity)
   local player_id = entity:get_player_id()
   local ownership_type = stonehearth.constants.healing.PRIORITY_CARE_OWNERSHIP_TYPE

   return stonehearth.ai:filter_from_key('stonehearth:sleep:sleep_in_priority_care_bed', player_id, function(target)
         if target:get_player_id() ~= player_id then
            return false
         end

         local bed_data = radiant.entities.get_entity_data(target, 'stonehearth:bed')
         if bed_data then
            local ownable_component = target:get_component('stonehearth:ownable_object')
            if bed_data.priority_care and not ownable_component and
                  not target:add_component('stonehearth:mount'):is_in_use() then
               return true
            end

            -- alternately, a bed can be considered for priority care if its assigned ownership is "medic patient"
            if ownable_component and ownable_component:get_reservation_type() == ownership_type then
               return true
            end
         end

         return false
      end)
end

return ace_shared_filters
