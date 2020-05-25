--[[
   in the "stonehearth:consumable" entity_data of the equipment/consumable entity:
   "script_info": {
      "condition": {
         "type": "or",   -- can be "and", "or", or a supported type (generally expressed as a component name)
         "conditions": [
            {
               "type": "stonehearth:expendable_resources",
               "resource_name": "health",
               "comparison": "<",
               "use_percent": true,
               "value": 0.70
            },
            {
               "type": "stonehearth:buffs",
               "buff_uri": "stonehearth:buffs:groggy",
               "has_buff": true
            }
         ]
      }
   }
]]

local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local UseConsumableOnCondition = class()

function UseConsumableOnCondition:on_buff_added(entity, buff)
   self._entity = entity
   self._buff = buff
   local equipment_comp = self._entity:get_component('stonehearth:equipment')
   local consumable = equipment_comp and equipment_comp:get_item_in_slot('consumable')
   if not consumable then
      return
   end
   local consumable_data = ConsumablesLib.get_consumable_data(consumable)
   self._use_condition = consumable_data and consumable_data.use_condition
   if not self._use_condition then
      return
   end

   -- set up triggers for when to use it
   self._listeners = {}
   self:_create_listeners(self._use_condition)
   self:_consider_using()
end

function UseConsumableOnCondition:_create_listeners(condition)
   if condition.type == 'and' or condition.type == 'or' then
      for _, sub_cond in ipairs(condition.conditions) do
         self:_create_listeners(sub_cond)
      end
   else
      if condition.type == 'stonehearth:expendable_resources' then
         self:_create_listener('stonehearth:expendable_resource_changed:' .. condition.resource_name)
      elseif condition.type == 'stonehearth:buffs' then
         if condition.has_buff ~= false then
            self:_create_listener('stonehearth:buff_added', function(args)
                  return args.uri == condition.buff_uri
               end)
         else
            self:_create_listener('stonehearth:buff_removed', function(uri)
                  return uri == condition.buff_uri
               end)
         end
      end
   end
end

function UseConsumableOnCondition:_create_listener(event_name, check_fn)
   if not self._listeners[event_name] then
      self._listeners[event_name] = radiant.events.listen(self._entity, event_name, function(args)
            if not check_fn or check_fn(args) then
               self:_consider_using()
            end
         end)
   end
end

function UseConsumableOnCondition:_consider_using()
   local check_fn = function()
      return self:_consider_using_condition(self._use_condition)
   end
   if check_fn() then
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:equipped_consumable:usable', check_fn)
   end
end

function UseConsumableOnCondition:_consider_using_condition(condition)
   if condition.type == 'and' then
      for _, sub_cond in ipairs(condition.conditions) do
         if not self:_consider_using_condition(sub_cond) then
            return false
         end
      end
      return true

   elseif condition.type == 'or' then
      for _, sub_cond in ipairs(condition.conditions) do
         if self:_consider_using_condition(sub_cond) then
            return true
         end
      end
      return false
      
   else
      if condition.type == 'stonehearth:expendable_resources' then
         -- supports <, <=, >, and >=
         local expendable_resources = self._entity:get_component('stonehearth:expendable_resources')
         if expendable_resources then
            local value
            if condition.use_percent then
               value = expendable_resources:get_percentage(condition.resource_name)
            else
               value = expendable_resources:get_value(condition.resource_name)
            end
            if value then
               return (condition.comparison == '<' and value < condition.value) or
                      (condition.comparison == '<=' and value <= condition.value) or
                      (condition.comparison == '>' and value > condition.value) or
                      (condition.comparison == '>=' and value >= condition.value)
            end
         end
      elseif condition.type == 'stonehearth:buffs' then
         local buffs = self._entity:get_component('stonehearth:buffs')
         if buffs then
            local result = false
            if condition.buff_uri then
               result = buffs:has_buff(condition.buff_uri)
            elseif condition.buff_category then
               result = buffs:has_category_buffs(condition.buff_category)
            end

            if condition.has_buff ~= false then
               return result
            else
               return not result
            end
         end
      end
   end
end

function UseConsumableOnCondition:on_buff_removed(entity, buff)
   if self._listeners then
      for _, listener in pairs(self._listeners) do
         listener:destroy()
      end
      self._listeners = nil
   end
end

return UseConsumableOnCondition
