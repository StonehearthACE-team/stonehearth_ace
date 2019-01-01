local shared_filters = require 'ai.filters.shared_filters'
local PetSleepInBed = radiant.class()

PetSleepInBed.name = 'sleep in pet bed'
PetSleepInBed.does = 'stonehearth:sleep'
PetSleepInBed.args = {}
PetSleepInBed.priority = 0.9

function available_pet_bed_filter(entity)
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

local ai = stonehearth.ai
return ai:create_compound_action(PetSleepInBed)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.CALL(available_pet_bed_filter, ai.ENTITY),
            description = 'sleep in pet bed'
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
        -- :execute('stonehearth:sleep_on_ground_adjacent')
         :execute('stonehearth_ace:pet_sleep_in_bed_adjacent', { bed = ai.BACK(1).entity })
