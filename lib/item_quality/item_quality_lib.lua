local rng = _radiant.math.get_default_rng()

local item_quality_lib = {}

function item_quality_lib.get_quality(quality, max_quality)
   if type(quality) == 'table' then
      return item_quality_lib.get_random_quality(quality, max_quality)
   else
      return math.min(quality or 1, max_quality or stonehearth.constants.item_quality.MASTERWORK)
   end
end

function item_quality_lib.get_random_quality(quality_chances, max_quality)
   local roll = rng:get_real(0, 1)
   local output_quality = 1
   if not max_quality then
      max_quality = stonehearth.constants.item_quality.MASTERWORK
   end

   local cumulative_chance = 0
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
         options = options or {}
         if options.override_allow_variable_quality == nil then
            options.override_allow_variable_quality = true
         end
         iq_comp:initialize_quality(quality, options and options.author, options and options.author_type, options)
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
   return (town and town:get_town_bonus('stonehearth:town_bonus:guildmaster') ~= nil
            and stonehearth.constants.item_quality.MASTERWORK)
            or stonehearth.constants.item_quality.EXCELLENT
end

function item_quality_lib.modify_quality_table(qualities, ingredient_quality)
   local modified_chances = {}
   for i=#qualities, 1, -1 do
      local value = qualities[i]
      local quality, chance = value[1], value[2]
      if i > 1 then
         chance = chance * (1 + 2 ^ (1 + ingredient_quality - quality) - 2 ^ (2 - quality))
      end
      modified_chances[i] = { quality, chance }
   end

   return modified_chances
end

return item_quality_lib