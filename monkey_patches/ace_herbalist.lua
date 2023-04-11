local log = radiant.log.create_logger('herbalist')

local HerbalistClass = radiant.mods.require('stonehearth.jobs.herbalist.herbalist')
local AceHerbalistClass = class()

AceHerbalistClass._ace_old__create_listeners = HerbalistClass._create_listeners
function AceHerbalistClass:_create_listeners()
   self:_ace_old__create_listeners()

   self._planter_action_listener = radiant.events.listen(self._sv._entity, 'stonehearth_ace:interact_herbalist_planter', self, self._on_herbalist_planter_interaction)
end

AceHerbalistClass._ace_old__remove_listeners = HerbalistClass._remove_listeners
function AceHerbalistClass:_remove_listeners()
   self:_ace_old__remove_listeners()

   if self._planter_action_listener then
      self._planter_action_listener:destroy()
      self._planter_action_listener = nil
   end
end

AceHerbalistClass._ace_old__on_healed_entity = HerbalistClass._on_healed_entity
function AceHerbalistClass:_on_healed_entity(args)
   self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'herbalist_treatments')
end

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

function AceHerbalistClass:_on_herbalist_planter_interaction(args)
   local exp = args.type and self._xp_rewards[args.type]
   if exp then
      -- modify it by the level of crop in the planter
      local level = args.level
      if level then
         exp = exp * math.sqrt(math.max(1, level))

         if args.products then
            -- maybe do something with this?
         end
      end

      self._job_component:add_exp(exp)
   end

   -- track this like a category craft
   if args.type == 'tend_planter' and args.category then
      self:add_category_proficiency('_tending_' .. args.category)
   end

   self._sv._entity:add_component('stonehearth_ace:statistics'):increment_stat('job_activities', 'herbalist_planters')
end

return AceHerbalistClass
