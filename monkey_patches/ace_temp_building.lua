local build_util = require 'stonehearth.lib.build_util'

local FixtureData = require 'stonehearth.lib.building.fixture_data'
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Cube3   = _radiant.csg.Cube3
local Color4   = _radiant.csg.Color4

local log = radiant.log.create_logger('build.temp_building')

local AceTempBuilding = class()

function AceTempBuilding:finish()
   for _, data in pairs(self._data) do
      data:deferred_build()
   end

   -- Figure out what the 'bottom' of the building is, and offset everyone by that amount.
   local min_y = 999999999
   local bounds
   for _, data in pairs(self._data) do
      local data_bounds = data:get_world_real_region():get_bounds()
      if data_bounds:get_area() > 0 then
         min_y = math.min(data_bounds.min.y, min_y)
         if not bounds then
            bounds = data_bounds
         else
            bounds:grow(data_bounds)
         end
      end
   end

   if not bounds then
      bounds = Cube3(Point3(0, 0, 0), Point3(1, 1, 1))
   end
   local mid = (bounds.max + bounds.min) / 2
   self._offset = Point3(-mid.x, -min_y, -mid.z):to_int()

   for _, data in pairs(self._data) do
      if data:get_uri() == FixtureData.URI then
         local f = radiant.entities.create_entity(data:get_fixture_uri(), {
            owner = self._entity
            })

         radiant.terrain.place_entity_at_exact_location(f, data:get_world_origin() + self._offset , {
               root_entity = self._entity,
               force_iconic = false,
            })
         radiant.entities.turn_to(f, data:get_rotation())
      else
         local r = Region3()
         local structure = radiant.entities.create_entity('stonehearth:build2:entities:temp_structure', { owner = self._entity })
         radiant.terrain.place_entity_at_exact_location(structure, self._offset, {root_entity = self._entity})
         local wr = data:get_world_real_region()
         r:add_region(wr:translated(self._offset))
         structure:get('region_collision_shape'):get_region():modify(function(cursor)
               cursor:copy_region(wr)
               cursor:set_tag(0)
               cursor:optimize('temp building')
            end)
         structure:get('destination'):get_region():modify(function(cursor)
               cursor:copy_region(wr)
            end)
         -- TODO: ugh, fix this when we get proper ownership.
         if data.get_wall_map then
            for _, walls in data:get_wall_map():each() do
               for _, wall in pairs(walls) do
                  local structure = radiant.entities.create_entity('stonehearth:build2:entities:temp_structure', { owner = self._entity })
                  local wr = wall:get_world_real_region()
                  r:add_region(wr:translated(self._offset))
                  radiant.terrain.place_entity_at_exact_location(structure, self._offset, {root_entity = self._entity})
                  structure:get('region_collision_shape'):get_region():modify(function(cursor)
                        cursor:copy_region(wr)
                        cursor:set_tag(0)
                        cursor:optimize('temp building')
                     end)
                  structure:get('destination'):get_region():modify(function(cursor)
                        cursor:copy_region(wr)
                     end)
               end
            end
         end

         self._region:add_region(build_util.calculate_building_terrain_cutout({r}))
      end
   end

   for _, data in pairs(self._data) do
      stonehearth.building:remove_data(data)
   end

   self._bounds = self._region:get_bounds()
   self._data = {}
end

return AceTempBuilding
