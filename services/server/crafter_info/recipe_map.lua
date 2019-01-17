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

   local last_key = table.remove(keys_table)
   local values = {}
   local possibles = self._map[last_key]

   if possibles then
      for value, count in pairs(possibles) do
         local full_match = true
         for _, key in ipairs(keys_table) do
            local bucket = self._map[key]
            if not bucket or not bucket[value] then
               full_match = false
               break
            end
         end

         if full_match then
            values[value] = count
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

   for value2, _ in pairs(self._map[key] or {}) do
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
