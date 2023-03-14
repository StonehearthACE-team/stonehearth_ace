local animal_filters = require 'stonehearth_ace.ai.filters.animal_filters'
local PastureAnimalSleepInBed = radiant.class()

PastureAnimalSleepInBed.name = 'sleep in pasture bed'
PastureAnimalSleepInBed.does = 'stonehearth_ace:pasture_animal_sleep_in_bed'
PastureAnimalSleepInBed.args = {}
PastureAnimalSleepInBed.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PastureAnimalSleepInBed)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.CALL(animal_filters.make_available_pet_bed_filter, ai.ENTITY),
            description = 'find best pet bed',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(1).destination_entity })
         :execute('stonehearth_ace:pasture_animal_sleep_in_bed_adjacent', { bed = ai.BACK(1).entity })
