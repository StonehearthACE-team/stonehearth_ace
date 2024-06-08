local constants = require('stonehearth.constants')
local Region3 = _radiant.csg.Region3
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local build_util = require 'stonehearth.lib.build_util'

local log = radiant.log.create_logger('build.structure_renderer')

local StructureRenderer = require 'stonehearth.renderers.structure.structure_renderer'
local AceStructureRenderer = class()

AceStructureRenderer._ace_old_destroy = StructureRenderer.__user_destroy
function AceStructureRenderer:destroy()
   self:_ace_old_destroy()
   self:_destroy_shape_nodes()
end

function AceStructureRenderer:_destroy_shape_nodes()
   if self._shape_nodes then
      for _, shape_node in ipairs(self._shape_nodes) do
         shape_node:destroy()
      end
      self._shape_nodes = nil
   end
end

function AceStructureRenderer:_update_render_node()
   -- Destination has the color!
   local shape = self._entity:get('destination'):get_region():get()

   local in_rpg = self._vision_mode_listener and self._vision_mode == 'rpg'
   if in_rpg then
      shape = shape - Region3(shape:get_bounds():translated(Point3(0, 1, 0)))
   end

   local material_regions = {}
   for cube in shape:each_cube() do
      local tag = cube.tag
      --log:debug('%s rendering cube %s with tag "%s"', self._entity, cube, tag or '[nil]')
      if tag then
         local mat = build_util.tag_to_material(tag)
         local material_region = material_regions[mat]
         if not material_region then
            material_region = Region3()
            material_regions[mat] = material_region
         end
         material_region:add_cube(cube)
      end
   end

   local default_material = constants.construction.DEFAULT_BUILDING_MATERIAL
   local materials = constants.construction.building_materials

   self:_destroy_shape_nodes()
   self._shape_nodes = {}

   for mat, material_region in pairs(material_regions) do
      local material = materials[mat] or default_material
      log:debug('%s rendering region with area %s with tag "%s" => material "%s"', self._entity, material_region:get_area(), mat, material)
      local shape_node = _radiant.client.create_voxel_node(self._parent_node, material_region, material, Point3(0.5, 0, 0.5))
      table.insert(self._shape_nodes, shape_node)
   end
end

return AceStructureRenderer
