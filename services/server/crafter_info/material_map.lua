local util = require 'stonehearth_ace.lib.util'

local MaterialMap = class()

--- Manage the entities' uris by storing a reference to them through material tags,
--- and then placing them in their respective bucket.


function MaterialMap:initialize()
   self._map = {}
   self._log = radiant.log.create_logger('material_map')
end

function MaterialMap:clear()
   self._map = {}
end

-- Adds `value` to all buckets in `keys`.
-- If one such value already exists, then do nothing.
--
function MaterialMap:add(keys, value)
   local keys_table = keys
   if type(keys) == 'string' then
      keys_table = radiant.util.split_string(keys, ' ')
   end

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
function MaterialMap:intersecting_values(keys)
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
function MaterialMap:contains(key, value1)
   for _, value2 in ipairs(self._map[key] or {}) do
      if util.deep_compare(value2, value1, true) then
         return true
      end
   end

   return false
end

return MaterialMap
