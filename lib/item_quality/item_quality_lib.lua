local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
local item_qualities = constants.item_quality
local crafting_constants = constants.crafting
local log = radiant.log.create_logger('item_quality_lib')

local item_quality_lib = {}

function item_quality_lib.get_quality(quality, max_quality)
   if type(quality) == 'table' then
      return item_quality_lib.get_random_quality(quality, max_quality)
   else
      return math.min(quality or 1, max_quality or item_qualities.MASTERWORK)
   end
end

function item_quality_lib.get_random_quality(quality_chances, max_quality)
   local roll = rng:get_real(0, 1)
   local output_quality = 1
   if not max_quality then
      max_quality = item_qualities.MASTERWORK
   end

   local cumulative_chance = 0
   -- sort quality chances table by quality descending
   -- so if standard quality gets bumped into the negatives and fine+ qualities exceed 100%
   -- the higher qualities will have their proper chances to be selected
   table.sort(quality_chances, function(a, b)
         return a[1] > b[1]
      end)
   for _, value in ipairs(quality_chances) do
      local quality, chance = value[1], value[2]
      cumulative_chance = cumulative_chance + chance
      if (roll <= cumulative_chance) then
         output_quality = math.min(quality, max_quality)
         break
      end
   end

   return output_quality
end

function item_quality_lib.copy_quality(from, to, options)
   local from_iq = from:get_component('stonehearth:item_quality')
   if from_iq and from_iq:get_quality() > 1 then
      options = options or {}
      options.author = from_iq:get_author_name()
      options.author_type = from_iq:get_author_type()
      item_quality_lib.apply_quality(to, from_iq:get_quality(), options)
   end
end

-- quality parameter can be a number or a table of random quality chances
function item_quality_lib.apply_qualities(items, quality, options)
   options = options or {}
   for _, item in pairs(items) do
      item_quality_lib.apply_quality(item, quality, options)
   end
end

-- this can potentially cause issues if the item already has a quality or is already in someone's inventory
-- such items should be filtered out before calling this function
-- quality parameter can be a number or a table of random quality chances
function item_quality_lib.apply_quality(item, quality, options)
   if type(quality) == 'table' then
      item_quality_lib.apply_random_quality(item, quality, options)
   else
      options = options or {}
      --log:debug('applying quality %s to %s (min_quality = %s)', quality, item, tostring(options.min_quality))
      if options.min_quality then
         quality = math.max(quality, options.min_quality)
      end
      if quality > 1 then
         -- allow replacing existing, lower item qualities (assume the item has properly been removed from inventories if necessary)
         local iq_comp = item:get_component('stonehearth:item_quality')
         if iq_comp then
            if iq_comp:get_quality() >= quality then
               return
            else
               item:remove_component('stonehearth:item_quality')
            end
         end
         iq_comp = item:add_component('stonehearth:item_quality')
         if options.override_allow_variable_quality == nil then
            options.override_allow_variable_quality = true
         end
         iq_comp:initialize_quality(quality, options.author, options.author_type, options)
      end
   end
end

function item_quality_lib.apply_random_quality(item, quality_chances, options)
   options = options or {}
   local max_quality = options.max_quality or 3
   if max_quality > 1 then
      local quality = item_quality_lib.get_random_quality(quality_chances, max_quality)
      item_quality_lib.apply_quality(item, quality, options)
   end
end

-- this could be extended to allow other conditions for allowing masterwork or higher (4+) random qualities
function item_quality_lib.get_max_random_quality(player_id)
   local town = stonehearth.town:get_town(player_id)
   local masterwork_town_bonus
   for town_bonus, check in pairs(constants.town_progression.MASTERWORK_QUALITY_UNLOCKING_BONUSES) do
      if town:get_town_bonus(tostring(town_bonus)) and check then
         masterwork_town_bonus = true
         break
      end
   end
   return (town and masterwork_town_bonus ~= nil
            and item_qualities.MASTERWORK)
            or item_qualities.EXCELLENT
end

function item_quality_lib.add_quality_tables(qt1, qt2)
   if not qt1 then
      return qt2
   end
   if not qt2 then
      return qt1
   end

   local qualities = {}
   local new_qt = {}
   for _, quality_chance in ipairs(qt1) do
      qualities[quality_chance[1]] = quality_chance[2]
   end
   for _, quality_chance in ipairs(qt2) do
      qualities[quality_chance[1]] = (qualities[quality_chance[1]] or 0) + quality_chance[2]
   end

   for i, value in pairs(qualities) do
      table.insert(new_qt, {i, value})
   end

   item_quality_lib._clean_quality_table(new_qt)
   return new_qt
end

function item_quality_lib.modify_quality_table(qualities, ingredient_quality)
   local modified_chances = {}
   for i = #qualities, 1, -1 do
      local value = qualities[i]
      local quality, chance = value[1], value[2]
      if quality > 1 then
         chance = chance * (1 + 2 ^ (1 + ingredient_quality - quality) - 2 ^ (2 - quality))
      end
      modified_chances[i] = { quality, chance }
   end

   item_quality_lib._clean_quality_table(modified_chances)
   return modified_chances
end

-- moved from crafter_component:_calculate_quality to allow for uses outside strictly crafting
function item_quality_lib.get_quality_table(hearthling, recipe_category, ingredient_quality)
   local quality_distribution = crafting_constants.ITEM_QUALITY_CHANCES
   -- Towns with the Guildmaster bonus can produce masterwork items.
   local town = stonehearth.town:get_town(hearthling:get_player_id())
   if town then
      for _, bonus in pairs(town:get_active_town_bonuses()) do
         if bonus.get_adjusted_item_quality_chances then
            quality_distribution = bonus:get_adjusted_item_quality_chances()
            break
         end
      end
   end

   local job_comp = hearthling:get_component('stonehearth:job')
   local job_level = job_comp:get_current_job_level()
   -- Make sure range falls between 1 and max number of levels listed in chances table
   local index = math.min(math.max(1, job_level), #quality_distribution)
   local base_chances_table = quality_distribution[index]

   -- Modify item quality chances based on the level requirement of the recipe
   -- ACE: also consider the ingredient quality, and change level multiplier to consider category proficiency instead
   local calculated_chances = {}
   local standard_quality_index
   local remaining = 1
   --local lvl_mult = recipe_lvl_req and (1 + (0.4 * (job_level - math.max(1, recipe_lvl_req)))) or 1
   local category_crafts_mult = 1
   if recipe_category then
      category_crafts_mult = 1 + (crafting_constants.CATEGORY_PROFICIENCY_MAX_HIGHER_QUALITY_MULT - 1) *
            math.min(1, job_comp:get_curr_job_controller():get_category_proficiency(recipe_category))
   end

   for i=#base_chances_table, 1, -1 do
      local value = base_chances_table[i]
      local quality, chance = value[1], value[2]
      if quality > 1 and remaining > 0 then
         local ing_mult = ingredient_quality and (1 + 2 ^ (1 + ingredient_quality - quality) - 2 ^ (2 - quality)) or 1
         chance = math.floor(1000 * chance * category_crafts_mult * ing_mult) * 0.001
      else
         chance = remaining
      end
      remaining = remaining - chance

      if remaining < 0 then
         chance = chance + remaining
         remaining = 0
      end

      calculated_chances[i] = { quality, chance }
      if quality == 1 then
         standard_quality_index = i
      end
   end

   if not standard_quality_index then
      calculated_chances[#calculated_chances + 1] = { 1, remaining }
      standard_quality_index = #calculated_chances
   end

   -- Check the hearthling's Inspiration stat to see if we need to add a (flat) bonus
   --  These bonuses come after all the multiplication, so they're somewhat more pronounced 
   --  for higher-tier items (going from e.g. 5%->7%) than low-tier (going from e.g. 34%->36%)

   local attributes_component = hearthling:get_component('stonehearth:attributes')
   if attributes_component then
      local inspiration = attributes_component:get_attribute('inspiration')
      if inspiration then
         --(as of this writing, this simply converts inspiration to a percentage 2->.02)
         local flat_quality_chance_modifier = inspiration * stonehearth.constants.attribute_effects.INSPIRATION_QUALITY_CHANCE_MODIFIER

         for i=#calculated_chances, 1, -1 do --repeat for only qualities > Standard
            if i ~= standard_quality_index then
               local value = calculated_chances[i]
               local quality, chance = value[1], value[2]
               --add our flat chance to this quality tier's chance
               local modifier = math.max(chance + flat_quality_chance_modifier, 0) - chance
               calculated_chances[i][2] = chance + modifier
               -- ...and remove it from Standard Quality
               calculated_chances[standard_quality_index][2] = math.max(calculated_chances[standard_quality_index][2] - modifier, 0)
            end
         end
      end
   end

   item_quality_lib._clean_quality_table(calculated_chances)
   return calculated_chances
end

function item_quality_lib.get_max_crafting_quality(player_id)
   -- Towns with the Guildmaster bonus can produce masterwork items.
   local quality = item_qualities.EXCELLENT or 3
   local town = stonehearth.town:get_town(player_id)
   if town then
      for _, bonus in pairs(town:get_active_town_bonuses()) do
         if bonus.get_max_crafting_quality then
            quality = bonus:get_max_crafting_quality()
         end
      end
   end
   
   return quality
end

function item_quality_lib._clean_quality_table(quality_table)
   local total = 0
   table.sort(quality_table, function(a, b)
         return a[1] > b[1]
      end)
   for _, value in ipairs(quality_table) do
      local quality, chance = value[1], value[2]
      if total == 1 then
         value[2] = 0
      else
         total = total + chance
         if total > 1 then
            chance = chance - (total - 1)
            value[2] = chance
            total = 1
         end
      end
   end
end

return item_quality_lib