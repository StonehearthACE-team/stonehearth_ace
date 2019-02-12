local animal_filters = require 'ai.filters.animal_filters'
local PastureAnimalSleepInBed = radiant.class()

PastureAnimalSleepInBed.name = 'sleep in pasture bed'
PastureAnimalSleepInBed.does = 'stonehearth:sleep'
PastureAnimalSleepInBed.args = {}
PastureAnimalSleepInBed.priority = 0.9

local ai = stonehearth.ai
return ai:create_compound_action(PastureAnimalSleepInBed)
         :execute('stonehearth_ace:pasture_animal_sleep_in_bed')