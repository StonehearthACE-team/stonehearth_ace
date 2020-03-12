local log = radiant.log.create_logger('herbalist')

local HerbalistClass = radiant.mods.require('stonehearth.jobs.herbalist.herbalist')
local AceHerbalistClass = class()

function AceHerbalistClass:increase_healing_item_effect(args)
   self._sv.healing_item_effect_multiplier = args.healing_item_effect_multiplier
   self.__saved_variables:mark_changed()
end

function AceHerbalistClass:get_healing_item_effect_multiplier()
   return self._sv.healing_item_effect_multiplier or 1
end

function AceHerbalistClass:increase_planter_tend_amount(args)
   self._sv.planter_tend_amount = args.planter_tend_amount
   self.__saved_variables:mark_changed()
end

function AceHerbalistClass:get_planter_tend_amount()
   return self._sv.planter_tend_amount or 1
end

return AceHerbalistClass
