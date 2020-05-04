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
   if any of the properties have any rules that evaluate to true, we don't want that item
   valid comparators are: ==, !=, <, <=, >, >=, none, any
]]

local no_items_with_property_value = {}

local _eval_property = function(value, rules)
   for _, rule in ipairs(rules) do
      if rule.comparator == 'none' and value == nil then
         return true
      elseif rule.comparator == 'any' and value ~= nil then
         return true
      elseif rule.comparator == '==' and value and value == rule.value then
         return true
      elseif rule.comparator == '!=' and value and value ~= rule.value then
         return true
      elseif rule.comparator == '<' and value and value < rule.value then
         return true
      elseif rule.comparator == '<=' and value and value <= rule.value then
         return true
      elseif rule.comparator == '>' and value and value > rule.value then
         return true
      elseif rule.comparator == '>=' and value and value >= rule.value then
         return true
      end
   end
end

function no_items_with_property_value.filter_entry(args, entry_data)
   for p, v in pairs(args) do
      if _eval_property(entry_data[p], v) then
         return false
      end
   end

   return true
end

function no_items_with_property_value.filter_item(args, item_data)
   for p, v in pairs(args) do
      if _eval_property(item_data[p], v) then
         return false
      end
   end

   return true
end

return no_items_with_property_value
