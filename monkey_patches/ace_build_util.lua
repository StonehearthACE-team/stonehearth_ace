local Region3 = _radiant.csg.Region3

local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local build_util = require 'stonehearth.lib.build_util'
local ace_build_util = {}

local log = radiant.log.create_logger('build_util')

function ace_build_util.get_all_material_counts(color_region)
   local all_material_counts = {}

   for cube in color_region:each_cube() do
      local tag = cube.tag
      local material = build_util.tag_to_material(tag)
      local count = all_material_counts[material] or 0
      all_material_counts[material] = count + cube:get_area()
   end

   return all_material_counts
end

function ace_build_util.calculate_building_terrain_cutout(regions)
   local cutout = Region3()

   for _, region in ipairs(regions) do
      local bounds = region:get_bounds()
      local r2 = region:project_onto_xz_plane()
      local r3 = radiant.terrain.intersect_region(csg_lib.get_convex_filled_region(r2):lift(bounds.min.y, bounds.max.y))
      if not r3:empty() then
         cutout:add_region(r3)
      end
   end

   return cutout
end

-- ACE: allow it to collide with root entity if it's also within valid terrain (e.g., in a room blueprint)
function ace_build_util._is_valid_stairs_location(location, options)
   local function can_contain_entity(entity, options)
      if entity:get_id() == radiant._root_entity_id then
         return options.valid_terrain_region and options.valid_terrain_region:contains(location)
      end

      if build_util.is_blueprint(entity) then
         return false
      end

      if build_util.is_fabricator(entity) then
         return false
      end

      if entity:get_component('stonehearth:fabricator') then
         return false
      end

      local rcs = entity:get_component('region_collision_shape')
      if rcs and rcs:get_region_collision_type() ~= _radiant.om.RegionCollisionShape.NONE then
         return false
      end

      return true
   end

   local entities = radiant.terrain.get_entities_at_point(location)
   for _, entity in pairs(entities) do
      if not can_contain_entity(entity, options) then
         return false
      end
   end

   return true
end

return ace_build_util
