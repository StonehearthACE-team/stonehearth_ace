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
   self._sv.require_matching_filter = self._json.require_matching_filter
end

function InputComponent:get_priority()
   return self._sv._priority
end

function InputComponent:set_priority(priority)
   self._sv._priority = priority
end

function InputComponent:try_input(item, force_add)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      -- if it has an iconic form, use that
      local entity_forms = item:get_component('stonehearth:entity_forms')
      if entity_forms then
         local iconic_entity = entity_forms:get_iconic_entity()
         if iconic_entity then
            item = iconic_entity
         end
      end

      if not self._sv.require_matching_filter or storage:passes(item) then
         -- if this storage is also a stockpile, we need to place it on the ground within its bounds instead, and let *that* put it into storage
         local stockpile = self._entity:get_component('stonehearth:stockpile')
         if stockpile then
            local output_location = radiant.entities.get_destination_location(self._entity)
            if output_location then
               radiant.terrain.place_entity(item, output_location)
               return true
            end
         else
            local forcing = not self._sv.require_matching_filter or force_add
            local result = storage:add_item(item, forcing, radiant.entities.get_player_id(self._entity))
            if forcing and result then
               stonehearth.ai:reconsider_entity(item, 'added item to storage')
            end
            return result
         end
      end
   end
end

-- either returns nil for a failed attempt, or returns a "lease" on a storage space
function InputComponent:can_input(item)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      -- if it has an iconic form, use that
      local entity_forms = item:get_component('stonehearth:entity_forms')
      if entity_forms then
         local iconic_entity = entity_forms:get_iconic_entity()
         if iconic_entity then
            item = iconic_entity
         end
      end

      if not self._sv.require_matching_filter or storage:passes(item) then
         return storage:reserve_space(nil, nil, 1)
      end
   end
end

return InputComponent
