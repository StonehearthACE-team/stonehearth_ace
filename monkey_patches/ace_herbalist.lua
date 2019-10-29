local log = radiant.log.create_logger('herbalist')

local HerbalistClass = radiant.mods.require('stonehearth.jobs.herbalist.herbalist')
local CraftingJob = require 'stonehearth.jobs.crafting_job'
local AceHerbalistClass = class()

function AceHerbalistClass:initialize()
   CraftingJob.__user_initialize(self)
   self._sv.max_num_attended_hearthlings = 2
end

function AceHerbalistClass:increase_healing_item_effect(args)
   self._sv.healing_item_effect_multiplier = args.healing_item_effect_multiplier
   self.__saved_variables:mark_changed()
end

function AceHerbalistClass:get_healing_item_effect_multiplier()
   return self._sv.healing_item_effect_multiplier or 1
end

return AceHerbalistClass
