local RecipeMap = class()

-- Manage the recipes by storing a reference to them through their uri and material tags,
-- and then placing them in their respective bucket.

function RecipeMap:initialize()
   self._map = {}
   self._log = radiant.log.create_logger('recipe_map')
end

-- Adds `value` to all buckets in `keys`.
-- If one such value already exists, then do nothing.
--
function RecipeMap:add(keys, value)
   local keys_table = radiant.util.split_string(keys, ' ')

   for _, key in ipairs(keys_table) do
      local bucket = self._map[key]
      if not bucket then
         bucket = {}
         self._map[key] = bucket
      end

      if not self:contains(key, value) then
         table.insert(bucket, value)
      end
   end
end

-- Returns a table containing all the values that share all within `keys`
--
function RecipeMap:intersecting_values(keys)
   local keys_table = radiant.util.split_string(keys, ' ')

   local last_key = table.remove(keys_table)
   local values = radiant.shallow_copy(self._map[last_key] or {})

   for _, key in ipairs(keys_table) do
      for index = radiant.size(values), 1, -1 do
         local value = values[index]
         if not self:contains(key, value) then
            table.remove(values, index)
         end
      end
   end

   return values
end

-- Checks if `value` is contained within `key`.
-- Returns true if it does, else false.
--
function RecipeMap:contains(key, value1)
   -- Compare what the two recipe produce and their ingredients, ugly but simple and efficient
   local v_prod1 = value1.recipe.produces
   local v_ingr1 = value1.recipe.ingredients
   value1 = {v_prod1, v_ingr1}

   for _, value2 in ipairs(self._map[key] or {}) do
      local v_prod2 = value2.recipe.produces
      local v_ingr2 = value2.recipe.ingredients
      value2 = {v_prod2, v_ingr2}
      if stonehearth_ace.util.deep_compare(value2, value1, true) then
         return true
      end
   end

   return false
end

return RecipeMap
