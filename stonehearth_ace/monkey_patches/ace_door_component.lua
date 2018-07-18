local DoorComponent = radiant.mods.require('stonehearth.components.door.door_component')
local AceDoorComponent = class()

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

-- we're not actually using this, but let's keep it around just in case
AceDoorComponent._old_add_collision_shape = DoorComponent._add_collision_shape

function AceDoorComponent:_add_collision_shape()
   local portal = self._entity:get_component('stonehearth:portal')
   if portal then
      local mob = self._entity:add_component('mob')
      local mgs = self._entity:add_component('movement_guard_shape')
	  local depth = math.max(1, portal:get_depth() or 1)

      local region2 = portal:get_portal_region()
      local region3 = mgs:get_region()
      if not region3 then
         region3 = radiant.alloc_region3()
         mgs:set_region(region3)
      end
      region3:modify(function(cursor)
            cursor:clear()
            for rect in region2:each_cube() do
				for z = 1, depth, 1 do
					cursor:add_unique_cube(Cube3(Point3(rect.min.x, rect.min.y,  z - 1),
												 Point3(rect.max.x, rect.max.y,  z)))
				end
            end
         end)
   end
end

return AceDoorComponent
