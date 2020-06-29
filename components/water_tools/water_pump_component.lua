--[[
   the core water functionality has been shifted to the water_sponge component
   now this component primarily handles the extendable pipe aspect
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local water_lib = require 'stonehearth_ace.lib.water.water_lib'

local log = radiant.log.create_logger('water_pump')

local WaterPumpComponent = class()

function WaterPumpComponent:initialize()
   self._json = radiant.entities.get_json(self)
end

function WaterPumpComponent:create()
	self._is_create = true
end

function WaterPumpComponent:restore()
	if self._sv.rate then
      -- old version of pump; needs to have its topper destroyed
      self._sv.rate = nil
      self._sv.depth = nil
      self._sv.height = nil
      self._sv.topper_region = nil
      if self._sv._pump_child_entity then
         radiant.entities.destroy_entity(self._sv._pump_child_entity)
         self._sv._pump_child_entity = nil
      end

      self.__saved_variables:mark_changed()
      self._is_create = true
   end
end

function WaterPumpComponent:activate()
   self._rotations = water_lib.get_water_pump_rotations(self._entity:get_uri())
end

function WaterPumpComponent:post_activate()
   if self._is_create then
      -- the child entity is only for the region collision shape, which needs to be solid while the pump's is platform
      -- rendering will still all happen on the main entity
      self._sv._pump_child_entity = radiant.entities.create_entity('stonehearth_ace:gizmos:water_pump_pipe', { owner = self._entity })
      self._sv._pump_child_entity:add_component('region_collision_shape'):set_region(_radiant.sim.alloc_region3())
      radiant.entities.add_child(self._entity, self._sv._pump_child_entity, Point3.zero)
   end
end

function WaterPumpComponent:destroy()
   --When the water tool is destroyed, destroy any other child entities
   if self._sv._pump_child_entity then
		radiant.entities.destroy_entity(self._sv._pump_child_entity)
		self._sv._pump_child_entity = nil
	end
end

-- whatever calls this should also call the water_sponge component's set_output_location
function WaterPumpComponent:set_pipe_extension(rotation_index, length, collision_region)
   local data
   local rotation = self._rotations[rotation_index]
   if rotation then
      local rcs = self._sv._pump_child_entity:add_component('region_collision_shape')
      rcs:get_region():modify(function(cursor)
         cursor:clear()
         cursor:copy_region(collision_region)
      end)

      data = radiant.shallow_copy(rotation)
      data.length = length
   end

   self._sv.pipe_render_data = data
   self.__saved_variables:mark_changed()
end

return WaterPumpComponent
