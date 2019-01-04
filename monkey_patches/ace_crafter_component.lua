local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local CrafterComponent = radiant.mods.require('stonehearth.components.crafter.crafter_component')
local log = radiant.log.create_logger('crafter')

local AceCrafterComponent = class()

local STANDARD_QUALITY_INDEX = 1

--If you stop being a crafter, b/c you're killed or demoted,
--drop all your stuff, and release your crafting order, if you have one.
function AceCrafterComponent:clean_up_order()
   self:_distribute_all_crafting_ingredients()
   if self._sv.curr_order then
      self._sv.curr_order:reset_progress(self._entity)   -- Paul: added entity reference for multiple-crafter compatibility
      self._sv.curr_order:set_crafting_status(self._entity, nil)  -- Paul: added entity reference for multiple-crafter compatibility
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

function AceCrafterComponent:produce_crafted_item(product_uri, recipe, ingredient_quality)
   local item = radiant.entities.create_entity(product_uri, { owner = self._entity })

   -- Set quality on an item
   local quality = self:_calculate_quality(recipe.level_requirement or 0, ingredient_quality or STANDARD_QUALITY_INDEX)
   item:add_component('stonehearth:item_quality'):initialize_quality(quality, self._entity, 'person')

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
   local quality_distribution = constants.crafting.ITEM_QUALITY_CHANCES
   -- Towns with the Guildmaster bonus can produce masterwork items.
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      for _, bonus in pairs(town:get_active_town_bonuses()) do
         if bonus.get_adjusted_item_quality_chances then
            quality_distribution = bonus:get_adjusted_item_quality_chances()
         end
      end
   end

   local job_level = self._entity:get_component('stonehearth:job'):get_current_job_level()
   -- Make sure range falls between 1 and max number of levels listed in chances table
   local index = math.min(math.max(1, job_level), #quality_distribution)
   local base_chances_table = quality_distribution[index]

   radiant.assert(job_level >= recipe_lvl_req, 'crafter lvl is lower than recipe required level')

   -- Modify item quality chances based on the level requirement of the recipe
   -- Paul: also consider the ingredient quality
   local calculated_chances = {}
   local remaining = 1
   for i=#base_chances_table, 1, -1 do
      local value = base_chances_table[i]
      local quality, chance = value[1], value[2]
      if i > 1 then
         chance = chance * (1 + (0.4 * (job_level - recipe_lvl_req))) * (1 + 2 ^ (1 + ingredient_quality - quality) - 2 ^ (2 - quality))
      else
         chance = remaining
      end
      remaining = remaining - chance

      calculated_chances[i] = { quality, chance }
   end

   -- Check the hearthling's Inspiration stat to see if we need to add a (flat) bonus
   --  These bonuses come after all the multiplication, so they're somewhat more pronounced 
   --  for higher-tier items (going from e.g. 5%->7%) than low-tier (going from e.g. 34%->36%)

   local attributes_component = self._entity:get_component('stonehearth:attributes')
   if attributes_component then
        local inspiration = attributes_component:get_attribute('inspiration')
        if inspiration then
            --(as of this writing, this simply converts inspiration to a percentage 2->.02)
            local flat_quality_chance_modifier = inspiration * stonehearth.constants.attribute_effects.INSPIRATION_QUALITY_CHANCE_MODIFIER

            for i=#calculated_chances, (STANDARD_QUALITY_INDEX+1), -1 do --repeat for only qualities > Standard
                local value = calculated_chances[i]
                local quality, chance = value[1], value[2]
                --add our flat chance to this quality tier's chance
                calculated_chances[i][2] = math.max(chance + flat_quality_chance_modifier, 0)
                -- ...and remove it from Standard Quality
                calculated_chances[STANDARD_QUALITY_INDEX][2] = calculated_chances[STANDARD_QUALITY_INDEX][2] - flat_quality_chance_modifier
            end
        end
    end

   -- Roll a quality based on the chances for each quality (for this job level)
   local roll = rng:get_real(0, 1)
   local cumulative_chance = 0
   local output_quality
   for _, value in ipairs(calculated_chances) do
      local quality, chance = value[1], value[2]
      cumulative_chance = cumulative_chance + chance
      if (roll <= cumulative_chance) then
         output_quality = quality
         break
      end
   end

   radiant.assert(output_quality, 'could not calculate an item quality')

   return output_quality
end

return AceCrafterComponent
