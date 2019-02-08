local DoorComponent = radiant.mods.require('stonehearth.components.door.door_component')
local AceDoorComponent = class()

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local log = radiant.log.create_logger('door')

-- we're not actually using this, but let's keep it around just in case
AceDoorComponent._ace_old_add_collision_shape = DoorComponent._add_collision_shape
AceDoorComponent._ace_old_toggle_lock = DoorComponent.toggle_lock

function AceDoorComponent:_add_collision_shape()
   local portal = self._entity:get_component('stonehearth:portal')
   if portal then
      local mob = self._entity:add_component('mob')
      local mgs = self._entity:add_component('movement_guard_shape')

      local region2 = portal:get_portal_region()
	   local is_horizontal = portal:is_horizontal()
      local region3 = mgs:get_region()
      if not region3 then
         region3 = radiant.alloc_region3()
         mgs:set_region(region3)
      end
      region3:modify(function(cursor)
            cursor:clear()
            for rect in region2:each_cube() do
				if is_horizontal then
					cursor:add_unique_cube(Cube3(Point3(rect.min.x, 0, rect.min.y),
												 Point3(rect.max.x, 1, rect.max.y)))
				else
					cursor:add_unique_cube(Cube3(Point3(rect.min.x, rect.min.y, 0),
												 Point3(rect.max.x, rect.max.y, 1)))
				end
            end
         end)
   end
end

function AceDoorComponent:toggle_lock()
	self:_ace_old_toggle_lock()

	-- now adjust its collision type
	local mod = self._entity:add_component('stonehearth_ace:entity_modification')
	if self._sv.locked then
		mod:set_region_collision_type('solid')
	else
		mod:reset_region_collision_type()
	end
end

return AceDoorComponent