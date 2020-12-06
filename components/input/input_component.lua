--[[
   complement to output component
   TODO: add filters, and add a filter parameter to try_input?

   setting priority to a higher number will make it a higher priority compared to other inputs when outputting to multiple inputs
   setting a max distance limits acceptable input items if a source is provided with those items
   setting output types limits acceptance of items to only entities with outputs of one of those types
]]

local InputComponent = class()

function InputComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   -- if no default priority, set it to an arbitrary negative value
   -- this way non-prioritized inputs are always sorted in a reliable (if somewhat arbitrary) order
   self._sv._priority = self._json.priority or -self._entity:get_id()
   self._sv._max_distance = self._json.max_distance
   self._sv._output_types = self._json.output_types
   self._sv.require_matching_filter = self._json.require_matching_filter
   self._sv.enabled = self._json.enabled ~= false
end

function InputComponent:get_priority()
   return self._sv._priority
end

function InputComponent:set_priority(priority)
   self._sv._priority = priority
end

function InputComponent:set_max_distance(distance)
   self._sv._max_distance = distance
end

function InputComponent:set_output_types(output_types)
   self._sv._output_types = output_types
end

function InputComponent:set_enabled(enabled)
   self._sv.enabled = enabled
   self.__saved_variables:mark_changed()
end

-- source can be a location (point), an entity, or nil/false
function InputComponent:_get_inputable_item(item, source)
   if not self._sv.enabled then
      return
   end
   
   if source then
      -- if the source is "output"-ing to this input, check that it's a valid type
      local output_comp = radiant.entities.is_entity(source) and source:get_component('stonehearth_ace:output')
      if not output_comp or (self._sv._output_types and not self._sv._output_types[output_comp:get_output_type()]) then
         return
      end

      -- if a source is specified and there's a max_distance for this input to collect from, cancel out
      if self._sv._max_distance and radiant.entities.distance_between(source, self._entity) > self._sv._max_distance then
         return
      end
   end

   -- if it has an iconic form, use that
   local entity_forms = item:get_component('stonehearth:entity_forms')
   if entity_forms then
      local iconic_entity = entity_forms:get_iconic_entity()
      if iconic_entity then
         return iconic_entity
      end
   end

   return item
end

-- source can be a location (point), an entity, or nil/false
-- force_add only bypasses the storage space limits (and the filter, if that setting is enabled), not explicit distance/type limits (should it?)
function InputComponent:try_input(item, source, force_add)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      local inputable_item = self:_get_inputable_item(item, source)

      if inputable_item and (not self._sv.require_matching_filter or storage:passes(inputable_item)) and (force_add or not storage:is_full()) then
         -- if this storage is also a stockpile, we need to place it on the ground within its bounds instead, and let *that* put it into storage
         local stockpile = self._entity:get_component('stonehearth:stockpile')
         if stockpile then
            local output_location = radiant.entities.get_destination_location(self._entity)
            if output_location then
               radiant.terrain.place_entity(inputable_item, output_location)
               return true
            end
         else
            local forcing = not self._sv.require_matching_filter or force_add
            local result = storage:add_item(inputable_item, forcing, radiant.entities.get_player_id(self._entity))
            if forcing and result then
               stonehearth.ai:reconsider_entity(inputable_item, 'added item to storage')
            end
            return result
         end
      end
   end
end

-- source can be a location (point), an entity, or nil/false
-- either returns nil for a failed attempt, or returns a "lease" on a storage space
function InputComponent:can_input(item, source)
   local storage = self._entity:get_component('stonehearth:storage')
   if storage then
      local inputable_item = self:_get_inputable_item(item, source)

      if inputable_item and (not self._sv.require_matching_filter or storage:passes(inputable_item)) then
         return storage:reserve_space(nil, nil, 1)
      end
   end
end

return InputComponent
