local item_quality_lib = {}

function item_quality_lib.get_random_quality(quality_chances)
   local roll = rng:get_real(0, 1)
   local output_quality = 1

   local cumulative_chance = 0
   for _, value in ipairs(quality_chances) do
      local quality, chance = value[1], value[2]
      cumulative_chance = cumulative_chance + chance
      if (roll <= cumulative_chance) then
         output_quality = quality
         break
      end
   end

   return output_quality
end

function item_quality_lib.copy_quality(from, to, force)
   local from_iq = from:get_component('stonehearth:item_quality')
   if from_iq and from_iq:get_quality() > 1 then
      local options = {}
      options.author = from_iq:get_author()
      options.author_type = from_iq:get_author_type()
      options.override_allow_variable_quality = force
      item_quality_lib.apply_quality_options(to, from_iq:get_quality(), options)
   end
end

-- this can potentially cause issues if the item already has a quality or is already in someone's inventory
-- such items should be filtered out before calling this function
function item_quality_lib.apply_quality(item, quality, force)
   item_quality_lib.apply_quality_options(item, quality, force and {override_allow_variable_quality = true})
end

function item_quality_lib.apply_quality_options(item, quality, options)
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
      iq_comp:initialize_quality(quality, options and options.author, options and options.author_type, options)
   end
end

function item_quality_lib.apply_random_quality(item, quality_chances, force)
   local quality = item_quality_lib.get_random_quality(quality_chances)
   item_quality_lib.apply_quality(item, quality, force)
end

function item_quality_lib.apply_random_qualities(items, quality_chances, force)
   for _, item in pairs(items) do
      item_quality_lib.apply_random_quality(item, quality_chances, force)
   end
end

return item_quality_lib