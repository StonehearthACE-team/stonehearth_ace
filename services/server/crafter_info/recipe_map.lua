local util = require 'stonehearth_ace.lib.util'

local RecipeMap = class()

-- Manage the recipes by storing a reference to them through their uri and material tags,
-- and then placing them in their respective bucket.

function RecipeMap:initialize()
   self._map = {}
   self._log = radiant.log.create_logger('recipe_map')
end

function RecipeMap:clear()
   self._map = {}
end

-- Adds `value` to all buckets in `keys`.
function RecipeMap:add(keys, value)
   local keys_table
   if type(keys) == 'string' then
      keys_table = radiant.util.split_string(keys, ' ')
      keys = {}
   else
      keys_table = radiant.keys(keys)
   end

   for _, key in ipairs(keys_table) do
      local bucket = self._map[key]
      if not bucket then
         bucket = {}
         self._map[key] = bucket
      end

      bucket[value] = keys[key] or 1
   end
end

-- Returns a table containing all the values that share all within `keys`
--
function RecipeMap:intersecting_values(keys)
   local keys_table = radiant.util.split_string(keys, ' ')

   local num_keys = #keys_table
   local values = {}
   local possibles = self._map[keys_table[1]]

   if possibles then
      for value, count in pairs(possibles) do
         local full_match = true
         for i = 2, #keys_table do
            local key = keys_table[i]
            local bucket = self._map[key]
            if not bucket or not bucket[value] then
               full_match = false
               break
            end
         end

         if full_match then
            -- also make sure the recipe produces all the keys in a single product
            -- for example, you wouldn't want something that produces a wooden bed with a cloth resource
            -- to be considered as producing "wood resource"
            -- also, each product of the recipe should have its count be included if it fully matches
            -- (this is already done properly for single-key calls of this function, e.g., just "wood")
            if num_keys > 1 then
               count = util.sum_where_all_keys_present(value.recipe.product_materials, value.recipe.products, keys_table)
            end

            if count > 0 then
               values[value] = count
            end
         end
      end
   end

   return values
end

return RecipeMap
