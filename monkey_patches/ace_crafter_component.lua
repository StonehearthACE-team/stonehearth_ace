local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local CrafterComponent = radiant.mods.require('stonehearth.components.crafter.crafter_component')
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local log = radiant.log.create_logger('crafter')

local AceCrafterComponent = class()

local STANDARD_QUALITY_INDEX = 1

AceCrafterComponent._ace_old_create = CrafterComponent.create
function AceCrafterComponent:create()
   local json = radiant.entities.get_json(self)
   if json and json.auto_crafter then
      self._is_auto_crafter = true
   else
      self:_ace_old_create()
   end
end

AceCrafterComponent._ace_old_activate = CrafterComponent.activate
function AceCrafterComponent:activate()
   if not self._is_auto_crafter then
      self:_ace_old_activate()
   end

   if not self._sv._best_crafts then
      self._sv._best_crafts = {}
   end
end

AceCrafterComponent._ace_old_post_activate = CrafterComponent.post_activate
function AceCrafterComponent:post_activate()
   if not self._is_auto_crafter then
      self:_ace_old_post_activate()
   end
end

function AceCrafterComponent:is_auto_crafter()
   return self._is_auto_crafter
end

--If you stop being a crafter, b/c you're killed or demoted,
--drop all your stuff, and release your crafting order, if you have one.
function AceCrafterComponent:clean_up_order()
   self:_distribute_all_crafting_ingredients()
   if self._sv.curr_order then
      self._sv.curr_order:reset_progress(self._entity)   -- Paul: added entity reference for multiple-crafter compatibility
      self._sv.curr_order:set_crafting_status(self._entity, false)  -- Paul: added entity reference for multiple-crafter compatibility
      self._sv.curr_order = nil
   end
   if self._sv.curr_workshop then
      if self._sv.curr_workshop:is_valid() then
         local workshop_component = self._sv.curr_workshop:get_component('stonehearth:workshop')
         workshop_component:cancel_crafting_progress()
      end
      self._sv.curr_workshop = nil
   end
   self.__saved_variables:mark_changed()
end

function AceCrafterComponent:produce_crafted_item(product_uri, recipe, ingredients, ingredient_quality)
   local item = radiant.entities.create_entity(product_uri, { owner = self._entity })

   -- Set quality on an item; don't bother doing it if variable quality is explicitly denied
   local item_quality_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:item_quality', false)
   if not (item_quality_data and (item_quality_data.variable_quality == false)) then
      local quality = self:_calculate_quality(recipe.level_requirement or 0, ingredient_quality or STANDARD_QUALITY_INDEX)
      item:add_component('stonehearth:item_quality'):initialize_quality(quality, self._entity, 'person')
   end
   self:_update_best_crafts(item)

   -- if it's a pile item, add the ingredients to the pile component
   local pile_comp = item:get_component('stonehearth_ace:pile')
   if pile_comp then
      pile_comp:set_items(ingredients)
   end

   -- Return iconic form of entity if it exists
   local entity_forms = item:get_component('stonehearth:entity_forms')
   if entity_forms then
      local iconic_entity = entity_forms:get_iconic_entity()
      if iconic_entity then
         item = iconic_entity
      end
   end

   return item
end

function AceCrafterComponent:_calculate_quality(recipe_lvl_req, ingredient_quality)
   local quality_table = item_quality_lib.get_quality_table(self._entity, recipe_lvl_req, ingredient_quality)
   local output_quality = item_quality_lib.get_quality(quality_table)
   return output_quality
end

function AceCrafterComponent:get_best_crafts()
   return self._sv._best_crafts
end

function AceCrafterComponent:_update_best_crafts(item)
   local quality = radiant.entities.get_item_quality(item)
   
   if quality >= stonehearth.constants.persistence.crafters.MIN_QUALITY_BEST_CRAFTS then
      local best_crafts = self._sv._best_crafts
      table.insert(best_crafts, {uri = item:get_uri(), quality = quality})

      -- if there are more than the directed number of best crafts, remove the oldest lowest quality ones
      local num_stored = stonehearth.constants.persistence.crafters.NUM_BEST_CRAFTS_STORED
      while best_crafts[num_stored + 1] do
         local worst_index = 1
         for i = 1, #best_crafts do
            if best_crafts[i].quality < best_crafts[worst_index].quality then
               worst_index = i
            end
         end
         table.remove(best_crafts, worst_index)
      end

      --self.__saved_variables:mark_changed()
   end
end

-- don't just call the old function; we need to actually check if the happiness component is relevant (could be an auto-crafter)
function AceCrafterComponent:get_work_rate()
   -- Note: Job multiplier is turned off because we haven't had the chance to balance check it
   -- local job_level = self._entity:get_component('stonehearth:job'):get_current_job_level()
   -- assert(job_level >= 0)
   -- local job_multiplier = 1 + (job_level - 1) * 0.20
   local tiredness_multiplier = radiant.entities.has_buff(self._entity, 'stonehearth:buffs:groggy') and 0.75 or 1
   local happiness_comp = self._entity:get_component('stonehearth:happiness')
   local mood_multiplier = happiness_comp and happiness_comp:get_mood_work_rate_multiplier() or 1

   local multiplier = self._entity:get_component('stonehearth:attributes'):get_attribute('multiplicative_work_rate_modifier', 1)

   return multiplier * tiredness_multiplier * mood_multiplier -- * job_multiplier
end

function AceCrafterComponent:get_fuel_reserved_workshop()
   return self._fuel_reserved_workshop
end

function AceCrafterComponent:set_fuel_reserved_workshop(workshop)
   self._fuel_reserved_workshop = workshop
end

function AceCrafterComponent:unreserve_fuel()
   local workshop_component = self._fuel_reserved_workshop and self._fuel_reserved_workshop:get_component('stonehearth:workshop')
   if workshop_component then
      workshop_component:unreserve_fuel(self._entity:get_id())
   end
end

return AceCrafterComponent
