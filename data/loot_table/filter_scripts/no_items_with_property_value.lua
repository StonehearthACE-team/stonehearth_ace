--[[
   expects args to be a table of property name keys with rule table values:
   {
      "property1": [
         {
            "comparator": ">="
            "value": 5
         }
      ]
   }
]]

local util = require 'stonehearth_ace.lib.util'
local _eval_property = util.eval_property_or
local no_items_with_property_value = {}

-- if any of the properties have any rules that evaluate to true, we don't want that item
function no_items_with_property_value.filter_entry(args, entry_data)
   for p, v in pairs(args) do
      if _eval_property(entry_data[p], v) then
         return false
      end
   end

   return true
end

function no_items_with_property_value.filter_item(args, item_data, entry_data)
   for p, v in pairs(args) do
      if _eval_property(item_data[p], v) then
         return false
      end
   end

   return true
end

return no_items_with_property_value
