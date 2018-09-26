local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('wilderness_signal')
local wilderness_util = require 'lib.wilderness.wilderness_util'

local WildernessSignalComponent = class()

function WildernessSignalComponent._wild_filter_fn(entity)
   -- determine if we care about this entity in our region
   return wilderness_util.has_wilderness_value(entity)
end

function WildernessSignalComponent:initialize()
   self._sv.wild_entities = {}
   self._sv._wild_listeners = {}
   self._sv.wilderness_values = {}
   self._sv.wilderness_value = 0
   
   local json = radiant.entities.get_json(self)
   local region = json and json.signal_region and Region3(json.signal_region)
   if region then
      self:set_region(region)
   end
   
	self.__saved_variables:mark_changed()
end

function WildernessSignalComponent:create()
	self._is_create = true
end

function WildernessSignalComponent:post_activate()
   if not self._sv.signal_region then
      local component = self._entity:get_component('region_collision_shape')
      if component then
         self:set_region(component:get_region():get())
      else
         component = self._entity:get_component('destination')
         if component then
            self:set_region(component:get_region():get())
         else
            self:set_region(Region3(Cube3(Point3.zero, Point3.one)))
         end
      end
   end
	self:_startup()
end

function WildernessSignalComponent:destroy()
	self:_shutdown()
end

function WildernessSignalComponent:set_region(region, region_area)
   local location = radiant.entities.get_world_grid_location(self._entity)
   if location then
      self._sv.signal_region = region:translated(location)
      self._sv.signal_region_area = region_area or math.max(region:get_area(), 1)
      self:_reset()
   end
end

function WildernessSignalComponent:add_entity(entity)
   self:_on_entity_added(entity:get_id(), entity)
end

function WildernessSignalComponent:remove_entity(entity)
   self:_on_entity_removed(entity:get_id(), entity)
end

function WildernessSignalComponent:get_entity_wilderness_value(entity)
   return self._sv.wilderness_values[entity:get_id()]
end

function WildernessSignalComponent:get_wilderness_value()
   return (self._sv.wilderness_value or 0) / (self._sv.signal_region_area or 1)
end

function WildernessSignalComponent:update_entity_wilderness_value(entity, value)
   local prev_value = self:get_entity_wilderness_value(entity)
   if prev_value then
      value = self:_set_entity_value(entity, value)
      self._sv.wilderness_value = self._sv.wilderness_value - prev_value
      self.__saved_variables:mark_changed()
      if value ~= 0 then
         self:_trigger_changed_event()
      end
   else
      self:add_entity(entity, value)
   end
end

function WildernessSignalComponent:_startup()
   local on_entity_added = function(entity_id, entity)
      self:_on_entity_added(entity_id, entity)
   end
   local on_entity_removed = function(entity_id, entity)
      self:_on_entity_removed(entity_id, entity)
   end
	self._world_entity_trace = radiant.terrain.trace_world_entities('wilderness signal', on_entity_added, on_entity_removed)
end

function WildernessSignalComponent:_shutdown()
	if self._world_entity_trace then
		self._world_entity_trace:destroy()
		self._world_entity_trace = nil
   end
   self:_remove_all_wild_listeners()
end

function WildernessSignalComponent:_reset()
   self._sv.wilderness_values = {}
   self._sv.wilderness_value = 0
   
   if self._sv.signal_region then
      self._sv.wild_entities = radiant.terrain.get_entities_in_region(self._sv.signal_region, self._wild_filter_fn)
      for entity_id, entity in pairs(self._sv.wild_entities) do
         self:_add_entity(entity_id, entity)
      end
      self:_trigger_changed_event()
   else
      self._sv.wild_entities = {}
      self:_remove_all_wild_listeners()
   end

	self.__saved_variables:mark_changed()
end

function WildernessSignalComponent:_set_entity_value(entity, value)
   value = value or wilderness_util.get_value_from_entity(entity, nil, self._sv.signal_region)
   local entity_id = entity:get_id()
   self._sv.wilderness_values[entity_id] = value
   self._sv.wilderness_value = self._sv.wilderness_value + value
   self:_create_wild_listener(entity_id, entity)
   return value
end

function WildernessSignalComponent:_add_entity(entity_id, entity)
   if not self._sv.wilderness_values[entity_id] then
      return self:_set_entity_value(entity) ~= 0
   end
   return false
end

function WildernessSignalComponent:_remove_entity(entity_id, entity)
   local value = self._sv.wilderness_values[entity_id]
   if value then
      self._sv.wilderness_values[entity_id] = nil
      self._sv.wilderness_value = self._sv.wilderness_value - value
      self:_remove_wild_listener(entity_id)
      return value ~= 0
   end
   return false
end

function WildernessSignalComponent:_create_wild_listener(entity_id, entity)
   if not self._sv._wild_listeners[entity_id] then
      self._sv._wild_listeners[entity_id] = radiant.events.listen(entity, 'stonehearth_ace:wilderness:wilderness_value_changed', function(value)
         self:update_entity_wilderness_value(entity, value)
      end)
   end
end

function WildernessSignalComponent:_remove_wild_listener(entity_id)
   if self._sv._wild_listeners[entity_id] then
      self._sv._wild_listeners[entity_id]:destroy()
      self._sv._wild_listeners[entity_id] = nil
   end
end

function WildernessSignalComponent:_remove_all_wild_listeners()
   for _, listener in pairs(self._sv._wild_listeners) do
      listener:destroy()
   end
   self._sv._wild_listeners = {}
end

function WildernessSignalComponent:_on_entity_added(entity_id, entity)
   if self:_add_entity(entity_id, entity) then
      self:_trigger_changed_event()
   end
   self.__saved_variables:mark_changed()
end

function WildernessSignalComponent:_on_entity_removed(entity_id, entity)
   if self:_remove_entity(entity_id, entity) then
      self:_trigger_changed_event()
   end
   self.__saved_variables:mark_changed()
end

function WildernessSignalComponent:_trigger_changed_event()
   radiant.events.trigger(self._entity, 'stonehearth_ace:wilderness_signal:wilderness_value_changed', self:get_wilderness_value())
end

return WildernessSignalComponent