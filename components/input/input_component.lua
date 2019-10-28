--[[
   complement to output component
   TODO: add filters, and add a filter parameter to try_input?
]]

local InputComponent = class()

function InputComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   -- if no default priority, set it to an arbitrary negative value
   -- this way non-prioritized inputs are always sorted in a reliable (if somewhat arbitrary) order
   self._sv._priority = self._json.priority or -self._entity:get_id()
end

function InputComponent:get_priority()
   return self._sv._priority
end

function InputComponent:set_priority(priority)
   self._sv._priority = priority
end

function InputComponent:try_input(item)
   local storage = self._entity:get_component('stonehearth:storage')
   return storage and storage:add_item(item, false, radiant.entities.get_player_id(self._entity))
end

return InputComponent
