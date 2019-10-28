--[[
   provides an interface for dealing with the output products of entities
   e.g., harvesting crops, resource nodes, rrns; loot drops, mining drops, etc.
      - can specify default behavior (e.g., don't do anything, drop in random location within 1-3 voxels)
      - can "connect" input interfaces that are prioritized over default behavior
]]

local item_io_lib = require 'stonehearth_ace.lib.item_io.item_io_lib'

local OutputComponent = class()

function OutputComponent:initialize()
   self._sv.inputs = {}
   self._json = radiant.entities.get_json(self)
end

function OutputComponent:activate()
   -- TODO: load up default settings from json and any saved overrides
end

function OutputComponent:has_input(input_id, check_parents)
   if self._sv.inputs[input_id] ~= nil then
      return true
   end

   local parent = check_parents and self._sv.parent_output and self._sv.parent_output:get_component('stonehearth_ace:output')
   if parent then
      return parent:has_input(input_id, check_parents)
   end
end

function OutputComponent:has_any_input(check_parents)
   if next(self._sv.inputs) ~= nil then
      return true
   end

   local parent = check_parents and self._sv.parent_output and self._sv.parent_output:get_component('stonehearth_ace:output')
   if parent then
      return parent:has_any_input(check_parents)
   end
end

function OutputComponent:get_inputs()
   return self._sv.inputs
end

function OutputComponent:add_input(input)
   local id = input and input:is_valid() and input:get_id()
   if id then  
      self._sv.inputs[id] = input
      self.__saved_variables:mark_changed()
   end
end

function OutputComponent:remove_input(input)
   local id = input and input:is_valid() and input:get_id()
   if id then  
      self._sv.inputs[id] = nil
      self.__saved_variables:mark_changed()
   end
end

function OutputComponent:get_parent_output()
   return self._sv.parent_output
end

function OutputComponent:set_parent_output(output)
   self._sv.parent_output = output
   self.__saved_variables:mark_changed()
end

return OutputComponent
