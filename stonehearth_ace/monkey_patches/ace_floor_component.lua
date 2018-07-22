local build_util = require 'lib.build_util'

local Point2 = _radiant.csg.Point2
local Region3 = _radiant.csg.Region3
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local TraceCategories = _radiant.dm.TraceCategories

local Floor = radiant.mods.require('stonehearth.components.floor.floor_component')
local AceFloor = class()

-- this modified component adds the capability to add fixtures to floors (i.e., hatches)

-- this code was originally brought over from wall_component

-- enumerate the range (-2, -2) - (2, 2) in the order which is most
-- likely the least visually disturbing to the user
local TWEAK_OFFSETS = {
   Point3( 1, 0, 0),
   Point3(-1, 0, 0),
   Point3( 0, 0, -1),
   Point3( 0, 0, 1),

   Point3( 1, 0, -1),
   Point3(-1, 0, -1),
   Point3( 1, 0, 1),
   Point3(-1, 0, 1),

   Point3( 2, 0, 0),
   Point3(-2, 0, 0),
   Point3( 2, 0, -1),
   Point3(-2, 0, -1),
   Point3( 2, 0, 1),
   Point3(-2, 0, 1),

   Point3( 0, 0, -2),
   Point3( 0, 0, 2),
   Point3( 1, 0, -2),
   Point3( 1, 0, 2),
   Point3(-1, 0, -2),
   Point3(-1, 0, 2),
   Point3( 2, 0, -2),
   Point3( 2, 0, 2),
   Point3(-2, 0, -2),
   Point3(-2, 0, 2),
}

function AceFloor:layout()
	local building = build_util.get_building_for(self._entity)
	if not building and not self._editing_region then
		-- sometimes, depending on the order that things get destroyed, a wall
		-- will be asked to layout after it has been divorces from it's building
		-- (e.g. when the blueprint still exists, but the project (and thus the
		-- fabricator) has been destroyed).
		return
	end

	local collision_shape = self._entity:get_component('destination'):get_region():get()
	if self._editing then
		-- client side...
		if not self._editing_region then
			self._editing_region = _radiant.client.alloc_region3()
			self._editing_region:modify(function(cursor)
				cursor:copy_region(collision_shape)
			end)
		end
		collision_shape = Region3()
		collision_shape:copy_region(self._editing_region:get())
	end

	assert(collision_shape)
	assert(collision_shape:is_homogeneous())

	local to_remove = {}
	-- stencil out the hatches
	local ec = self._entity:get_component('entity_container')
	if ec then
		for _, child in ec:each_child() do
			local portal = child:get_component('stonehearth:portal')
			if portal and portal:is_horizontal() then
				local region3 = self:_get_portal_region(child, portal)

				if collision_shape:intersect_region(region3):get_area() == region3:get_area() then
					collision_shape:subtract_region(region3)
				else
					-- if there wasn't a full intersection, maybe room resizing moved it over the edge?
					table.insert(to_remove, child)
				end
			end
		end
	end

	for _, child in ipairs(to_remove) do
		stonehearth.build:unlink_entity(child)
	end

	self._entity:add_component('stonehearth:construction_progress')
					:paint_on_local_region(self._sv.brush, collision_shape, true)

	return self
end

function AceFloor:_get_portal_region(portal_entity, portal)
   local mob = portal_entity:get_component('mob')
   local origin = mob:get_grid_location()
   local rotation = radiant.entities.get_facing(portal_entity)

   local region2 = portal:get_portal_region()
   local region3 = Region3()
   for r2 in region2:each_cube() do
      local min = Point3(0, 0, 0)
      local max = Point3(0, 1, 0)

      min.x = r2.min.x
      max.x = r2.max.x
      min.z = r2.min.y
      max.z = r2.max.y

      local cube = Cube3(min, max)
      region3:add_unique_cube(cube)
   end

   return region3:rotated(rotation):translated(origin)
end

function AceFloor:compute_fixture_placement(fixture_entity, location)
   -- if there's no fixture component, it cannot be placed on the floor as a fixture
   local fixture = fixture_entity:get_component('stonehearth:fixture')
   if not fixture then
      return nil
   end

   -- if there's a portal component, make sure the fixture goes in the
   -- floor.  otherwise, it must be up 1
   local portal = fixture_entity:get_component('stonehearth:portal')
   if portal then
      location.y = 0
   else
      location.y = 1
   end
   
   -- make sure the fixture fits within its margin constraints
   local bounds = fixture:get_bounds()
   local margin = fixture:get_margin()
   local bounds3 = Cube3(Point3(bounds.min.x - margin.left, 0, bounds.min.y - margin.top),
						 Point3(bounds.max.x + margin.right, 0, bounds.max.y + margin.bottom))
						:rotated(radiant.entities.get_facing(fixture_entity))
						:translated(location)
   
   local box = Region3(bounds3)

   local shape = self._editing_region:get()
   local overhang = box - shape

   if overhang:empty() then
      return location
   end

   -- try to nudge it over.  if that doesn't work, bail.
   for _, tweak in ipairs(TWEAK_OFFSETS) do
      local offset = Point3(tweak.x, tweak.y, tweak.z)
      if (box:translated(offset) - shape):empty() then
         return location:translated(offset)
      end
   end

   -- no luck!
   return nil
end

function AceFloor:add_fixture(fixture, location, rotation)
	radiant.entities.add_child(self._entity, fixture, location)
	radiant.entities.turn_to(fixture, rotation or 0)

	return self
end

function AceFloor:remove_fixture(fixture)
   radiant.entities.remove_child(self._entity, fixture)
   return self
end

return AceFloor
