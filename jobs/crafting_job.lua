--[[
   ACE: overriding because combat classes mixin to this class, similar to BaseJob
   added tracking of category crafts
]]

-- Base class for all crafting jobs.
local BaseJob = require 'stonehearth.jobs.base_job'

local CraftingJob = class()
radiant.mixin(CraftingJob, BaseJob)

function CraftingJob:initialize()
   BaseJob.initialize(self)
end

function CraftingJob:promote(json_path, options)  
   BaseJob.promote(self, json_path)
   local crafter_component = self._sv._entity:add_component("stonehearth:crafter")
   crafter_component:set_json(self._job_json.crafter)
   self.__saved_variables:mark_changed()
end

-- Call when it's time to demote
function CraftingJob:demote()
   BaseJob.demote(self)
   self._sv._entity:get_component('stonehearth:crafter'):demote()
   self._sv._entity:remove_component("stonehearth:crafter")
   
   self.__saved_variables:mark_changed()
end

--- Private functions

function CraftingJob:_create_listeners()
   self._on_craft_listener = radiant.events.listen(self._sv._entity, 'stonehearth:crafter:craft_item', self, self._on_craft)
end

function CraftingJob:_remove_listeners()
   if self._on_craft_listener then
      self._on_craft_listener:destroy()
      self._on_craft_listener = nil
   end
end

--When we've crafted an item, we get XP according to the min-crafter level of the item
--If there is no level specified it's a default and should get that amount
--TODO: some items should give extra bonuses if they're really cool
function CraftingJob:_on_craft(args)
   local recipe_data = args.recipe_data

   local level_key = 'craft_level_0'
   local level_required = 0
   if recipe_data.level_requirement then
      level_key = 'craft_level_' .. recipe_data.level_requirement
      level_required = recipe_data.level_requirement
   end
   local job_level = self:get_job_level()
   local exp = self._xp_rewards[level_key]
   assert(exp, self._job_json.alias .. ' has no exp reward tuned for level ' .. level_key .. ' recipes')

   local exp_addition = 0
   local attributes_component = self._sv._entity:get_component('stonehearth:attributes')
   if attributes_component then
      local curiosity = attributes_component:get_attribute('curiosity')
      exp_addition = radiant.math.round(curiosity * stonehearth.constants.attribute_effects.CURIOSITY_EXPERIENCE_MULTIPLER)
      if exp_addition < 0 then
         exp_addition = 0
      end
   end

   exp = exp + exp_addition

   if level_required < job_level then
      local difference = job_level - level_required
      exp = exp / difference
   end
   exp = radiant.math.round(exp)
   self._job_component:add_exp(exp, false) -- false for do not apply curiosity addition because we've already done so

   -- ACE: added category craft tracking
   if recipe_data.category then
      self:add_category_proficiency(recipe_data.category, recipe_data.proficiency_gain)
   end
end

return CraftingJob