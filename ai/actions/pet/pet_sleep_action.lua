local animal_filters = require 'ai.filters.animal_filters'
local PetSleepInBed = radiant.class()

PetSleepInBed.name = 'sleep in pet bed'
PetSleepInBed.does = 'stonehearth:sleep'
PetSleepInBed.args = {}
PetSleepInBed.priority = 0.9

local ai = stonehearth.ai
return ai:create_compound_action(PetSleepInBed)
         :execute('stonehearth_ace:pet_sleep_in_bed')