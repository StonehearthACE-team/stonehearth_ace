-- ACE: override entire file because of all the local functions
-- loading fixture quality from templates should load quality 1 as -1

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Quaternion = _radiant.csg.Quaternion
local Region3 = _radiant.csg.Region3
local PolygonBuilder = _radiant.csg.PolygonBuilder

local FixtureData = require 'stonehearth.lib.building.fixture_data'
local RoofData = require 'stonehearth.lib.building.roof_data'
local RoomData = require 'stonehearth.lib.building.room_data'
local StairsData = require 'stonehearth.lib.building.stairs_data'
local WallData = require 'stonehearth.lib.building.wall_data'
local BlocksData = require 'stonehearth.lib.building.blocks_data'
local PerimeterWallData = require 'stonehearth.lib.building.perimeter_wall_data'
local WallMap = require 'stonehearth.lib.building.wall_map'
local RoadData = require 'stonehearth.lib.building.road_data'

local mutation_utils = require 'stonehearth.lib.building.mutation_utils'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local build_util = require 'stonehearth.lib.build_util'
local fixture_utils = require 'stonehearth.lib.building.fixture_utils'
local region_utils = require 'stonehearth.lib.building.region_utils'
local log = radiant.log.create_logger('build.template_utils')

local function _clean_bid(map, bidmap)
   local new_map = {}

   for bid, v in pairs(map) do
      local n = tonumber(bid)
      local bid = bidmap[n]
      if bid then
         new_map[bid] = v
      end
   end
   return new_map
end

local function _tuple_to_point3(tuple)
   --strip first and last char
   tuple = string.sub(tuple, 2, tuple:len() - 1)
   --split by ','
   local pts = radiant.util.split_string(tuple, ',')
   pts[2] = string.sub(pts[2], 2)
   pts[3] = string.sub(pts[3], 2)

   return Point3(tonumber(pts[1]), tonumber(pts[2]), tonumber(pts[3]))
end

local function _to_point3(json)
   return Point3(tonumber(json.x), tonumber(json.y), tonumber(json.z))
end

local function _to_point2(json)
   return Point2(tonumber(json.x), tonumber(json.y))
end

local function _to_polygon(json)
   local p = PolygonBuilder()
   for _, pt in ipairs(json) do
      p:add_point(_to_point2(pt))
   end
   return p:build()
end

local function _to_region3(json)
   local r = Region3()
   r:load(json)
   return r
end

function BuildingData_FromJson(json, bidmap)
   local b = {}

   b.bid = bidmap[tonumber(json.bid)]
   b.removed = json.removed
   b.origin = _to_point3(json.origin)
   b.fixtures = _clean_bid(json.fixtures, bidmap)
   b.masks = _clean_bid(json.masks, bidmap)
   b.masked = _clean_bid(json.masked, bidmap)
   b.hole_region = _to_region3(json.hole_region)
   b.supported = _clean_bid(json.supported, bidmap)
   b.invalid_placement = json.invalid_placement
   b.supports = _clean_bid(json.supports, bidmap)
   b.adjacent = _clean_bid(json.adjacent, bidmap)
   b.color_region = _to_region3(json.color_region)

   return b
end


function BlocksData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)
   local blocks = _to_region3(json.blocks)
   local brush = json.brush
   local kind = json.kind and tonumber(json.kind) or 0

   return BlocksData(building_id,
      b.bid,
      blocks,
      kind,
      b.origin,
      brush,
      b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.invalid_placement)
end

function RoadData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)
   local blocks = _to_region3(json.blocks)
   local brush = json.brush

   return RoadData(building_id,
                     b.bid,
                     blocks,
                     b.origin,
                     brush,
                     b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.invalid_placement)
end

function StairsData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)

   local p1, p2
   if json.perimeter then
      local p = _to_polygon(json.perimeter)
      p1 = p:get_bounds().min
      p2 = p:get_bounds().max
   else
      p1 = _to_point2(json.p1)
      p2 = _to_point2(json.p2)
   end
   local height = tonumber(json.height)
   local stride = tonumber(json.stride)
   local style = json.style
   local facing = json.facing
   local stairs_brush = json.stairs_brush

   return StairsData(building_id,
      b.bid,
      p1,
      p2,
      b.origin,
      height,
      stride,
      style,
      facing,
      stairs_brush,
      b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.color_region, b.invalid_placement)
end

function PerimeterWallData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)

   local wall_id = bidmap[tonumber(json.wall_id)]
   local brush = json.brush
   local key = _to_point3(json.key)
   local room_id = bidmap[tonumber(json.room_id)]
   local offset = tonumber(json.offset)
   local min = tonumber(json.min)
   local total_mask = _to_region3(json.total_mask)
   local max = tonumber(json.max)
   local p2 = _to_point2(json.p2)
   local p1 = _to_point2(json.p1)
   local column_brush = json.column_brush
   local height = tonumber(json.height)

   return PerimeterWallData(building_id, wall_id, room_id, p1, p2, offset, height, brush, column_brush,
      b.fixtures, total_mask, b.color_region, b.hole_region)
end

function WallData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)

   local brush = json.brush
   local p2 = _to_point2(json.p2)
   local p1 = _to_point2(json.p1)
   local column_brush = json.column_brush
   local height = tonumber(json.height)

   return WallData(building_id,
      b.bid,
      p1,
      p2,
      height,
      b.origin,
      brush,
      column_brush,
      b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.color_region, b.invalid_placement, b.hole_region)
end

function FixtureData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)
   local uri = json.uri
   local owner_bid = tonumber(json.owner_bid)
   if owner_bid ~= -1 then
      owner_bid = bidmap[owner_bid]
   end
   local direction = _to_point3(json.direction)
   local sub_data_bid
   if json.sub_data_bid then
      sub_data_bid = bidmap[tonumber(json.sub_data_bid)]
   end
   local rotation = tonumber(json.rotation)
   local quality = json.quality and tonumber(json.quality) or -1

   return FixtureData(building_id, b.bid, uri, quality, owner_bid, b.origin, direction, b.masked, sub_data_bid, rotation)
end

function RoomData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)

   local wall_map = WallMap_FromJson(json.wall_map, building_id, bidmap)
   local perimeter = _to_polygon(json.perimeter)
   local floor_brush = json.floor_brush
   local fusing = json.fusing

   return RoomData(building_id,
      b.bid,
      perimeter,
      wall_map,
      floor_brush,
      b.origin, b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.fusing, b.color_region, b.invalid_placement, b.hole_region)
end

function WallMap_FromJson(json, building_id, bidmap)
   local room_id = bidmap[tonumber(json.room_id)]
   local total_mask = _to_region3(json.total_mask)
   local lookup = radiant.alloc_point3_map()
   for pt, walls in pairs(json.lookup) do
      if pt ~= 'size' then
         local lookup_walls = {}
         pt = _tuple_to_point3(pt)
         for _, wall in ipairs(walls) do
            table.insert(lookup_walls, PerimeterWallData_FromJson(wall, building_id, bidmap))
         end
         lookup:add(pt, lookup_walls)
      end
   end

   return WallMap(room_id, total_mask, lookup)
end

function RoofData_FromJson(json, building_id, bidmap)
   local b = BuildingData_FromJson(json, bidmap)
   local wall_map = WallMap_FromJson(json.wall_map, building_id, bidmap)
   local perimeter = _to_polygon(json.perimeter)
   local roof_brush = json.roof_brush
   local wall_brush = json.wall_brush
   local column_brush = json.column_brush
   local options = json.options
   local fusing = json.fusing

   return RoofData(building_id,
      b.bid,
      perimeter,
      wall_map,
      b.origin,
      options,
      fusing,
      false,
      roof_brush,
      wall_brush,
      column_brush,
      b.fixtures, b.masks, b.masked, b.supports, b.supported, b.adjacent, b.color_region, b.invalid_placement, b.hole_region)
end


local template_utils = {}

function template_utils.get_major_version(version_string)
   if not version_string then
      return 0
   end
   return tonumber(string.sub(version_string, 1, 1)) or 0
end

function template_utils.save_template(building, template_id)
   local template
   template, template_id = template_utils.get_template_save_data(building, template_id)
   template_utils.save_template_data(template, template_id)
   return template
end

function template_utils.get_template_save_data(building, template_id)
   local bc = building:get('stonehearth:build2:building')
   bc:inc_revision()

   local template_id = bc:get_template_id()
   if not template_id then
      template_id = _radiant.sim.generate_uuid()
      bc:set_template_id(template_id)
   end
   local custom_name = radiant.entities.get_custom_name(building)

   local template = {
      header = {
         ['version'] = '1.0.0',
         ['custom_name'] = custom_name,
         ['file_name'] = template_id,
         ['revision'] = bc:get_revision(),
         ['preview_image'] = bc:get_template_icon(),
         ['sunk'] = bc:is_sunk(),
      },
      data = {},
   }

   for bid, bp in bc:get_blueprints():each() do
      -- clone the data, so that we can mask out some derived properties
      local data = bp:get('stonehearth:build2:blueprint'):get_data():_new({})
      data.shape = nil
      data.region = nil
      data.roof_shape = nil
      data.building_id = nil
      data.invalid_placement = false
      template.data[bid] = data
   end

   return template, template_id
end

function template_utils.save_template_data(template, template_id)
   _radiant.res.write_custom_building_template(template_id, template)
end

function template_utils.delete_template(template_id)
   return build_util.remove_template(template_id)
end

local function _json_to_data(json, fixtures, building_id, bidmap)
   local data
   if json.__classname == 'stonehearth:RoomData' then
      data = RoomData_FromJson(json, building_id, bidmap)
   elseif json.__classname == 'stonehearth:RoofData' then
      data = RoofData_FromJson(json, building_id, bidmap)
   elseif json.__classname == 'stonehearth:FixtureData' then
      data = FixtureData_FromJson(json, building_id, bidmap)
      fixtures[data:get_bid()] = data
   elseif json.__classname == 'stonehearth:WallData' then
      data = WallData_FromJson(json, building_id, bidmap)
   elseif json.__classname == 'stonehearth:StairsData' then
      data = StairsData_FromJson(json, building_id, bidmap)
   elseif json.__classname == 'stonehearth:BlocksData' then
      data = BlocksData_FromJson(json, building_id, bidmap)
   elseif json.__classname == 'stonehearth:RoadData' then
      data = RoadData_FromJson(json, building_id, bidmap)
   end

   return data
end

local function _json_to_blueprint(json, fixtures, building_id, bidmap, offset)
   local data = _json_to_data(json, fixtures, building_id, bidmap)

   if not data then
      return nil
   end

   if not data.get_owner_bid or data:get_owner_bid() == -1 then
      data.origin = data.origin + offset
   end

   if data:get_uri() ~= FixtureData.URI then
      local bp = radiant.entities.create_entity(data:get_uri())
      bp:get('stonehearth:build2:blueprint'):init(data)

      return bp
   end

   return nil
end

local function _collect_bids_from_data(json, bidmap)
   bidmap[tonumber(json.bid)] = 0
   if json.__classname == 'stonehearth:RoomData' or json.__classname == 'stonehearth:RoofData' then
      for pt, walls in pairs(json.wall_map.lookup) do
         if pt ~= 'size' then
            for _, wall in ipairs(walls) do
               bidmap[tonumber(wall.wall_id)] = 0
            end
         end
      end
   end
end

local function _bidmap_from_json(json_root, base_id)
   local bidmap = {}

   for _, json in pairs(json_root) do
      _collect_bids_from_data(json, bidmap)
   end

   local sorted_keys = radiant.keys(bidmap)
   table.sort(sorted_keys, function(a, b)
         return a < b
      end)

   for i, k in ipairs(sorted_keys) do
      bidmap[k] = i + base_id
   end

   return bidmap
end

function template_utils.load_template_as_temp(template_id, base_id)
   local template = template_utils.load_template_data(template_id)

   if not template.header.version then
      return template_utils.load_legacy_template_as_temp(template_id)
   end

   template.header.sunk = template.header.sunk ~= nil and template.header.sunk or false

   if not template.data then
      return nil, false
   end

   local bidmap = _bidmap_from_json(template.data, base_id)
   stonehearth.building:set_next_bid(radiant.size(bidmap) + base_id + 1)

   local building = radiant.entities.create_entity('stonehearth:build2:entities:temp_building')
   local bc = building:get('stonehearth:build2:temp_building')
   bc:set_template_id(template_id)
   local building_id = building:get_id()
   local fixtures = {}
   for _, json in pairs(template.data) do
      local data = _json_to_data(json, fixtures, building_id, bidmap)
      if data then
         bc:add_data(data)
      end
   end

   bc:finish()

   return building, template.header.sunk
end

function template_utils._legacy_structure_to_data(building_id, structure_kind, structure, offset, rotation)
   if structure_kind ~= 'stonehearth:fixture_fabricator' then
      local cr = structure:get('stonehearth:construction_progress'):get_color_region():get()
      local r = radiant.entities.local_to_world(cr, structure)

      local meta = stonehearth.constants.building.block_kinds.BLOCK
      if structure:get('stonehearth:wall') then
         local normal = structure:get('stonehearth:wall'):get_normal()
         if normal.x == 1 then
            meta = stonehearth.constants.building.block_kinds.WALL_E
         elseif normal.x == -1 then
            meta = stonehearth.constants.building.block_kinds.WALL_W
         elseif normal.z == 1 then
            meta = stonehearth.constants.building.block_kinds.WALL_N
         else
            meta = stonehearth.constants.building.block_kinds.WALL_S
         end

         local n = 4 - ((((rotation % 360) + 360) % 360) / 90)
         meta = (((meta - stonehearth.constants.building.block_kinds.WALL_N) + n) % 4) + stonehearth.constants.building.block_kinds.WALL_N

      elseif structure:get('stonehearth:roof') then
         meta = stonehearth.constants.building.block_kinds.ROOF
      end

      return BlocksData.MakeFromBlocks(
         building_id,
         offset,
         r, nil, nil, meta)
   end
   local ff = structure:get('stonehearth:fixture_fabricator')
   local uri = ff:get_uri()
   local rot = radiant.entities.get_facing(structure)
   local pos = radiant.entities.get_world_location(structure)
   local dir = ff:get_normal()
   return FixtureData.Make(
      building_id,
      stonehearth.building:get_next_bid(),
      uri,
      -1,
      -1,
      pos + offset,
      dir,
      nil,
      rot)
end

function template_utils.load_legacy_template_as_temp(template_id)
   local building = radiant.entities.create_entity('stonehearth:build2:entities:temp_building')
   local bc = building:get('stonehearth:build2:temp_building')
   bc:set_template_id(template_id)
   local building_id = building:get_id()
   local fixtures = {}

   local old_building = radiant.entities.create_entity('stonehearth:build:prototypes:building')
   build_util.restore_template(old_building, template_id, { mode = 'conversion' })
   radiant.terrain.place_entity_at_exact_location(old_building, Point3.zero)

   local old_bc = old_building:get_component('stonehearth:building')
   for structure_kind, structures in pairs(old_bc:get_all_structures()) do
      for _, entry in pairs(structures) do
         local data = template_utils._legacy_structure_to_data(building_id, structure_kind, entry.entity, Point3.zero, 0)
         bc:add_data(data)
      end
   end
   bc:finish()
   radiant.entities.destroy_entity(old_building)

   return building, false
end

function template_utils.load_legacy_template(building, template_id, base_id, offset, rot_point, rotation, template)
   local bc = building:get('stonehearth:build2:building')
   local building_id = building:get_id()

   bc:set_template_id(_radiant.sim.generate_uuid())
   bc:set_revision(1)
   bc:set_template_icon(template.header.preview_image)
   if template.header.custom_name then
      radiant.entities.set_custom_name(building, template.header.custom_name)
   end
   template.header.sunk = false

   local old_building = radiant.entities.create_entity('stonehearth:build:prototypes:building', { owner = radiant.entities.get_player_id(building)})
   radiant.terrain.place_entity_at_exact_location(old_building, Point3.zero)
   build_util.restore_template(old_building, template_id, { mode = 'conversion' })
   local fixtures = {}
   local old_bc = old_building:get_component('stonehearth:building')
   for structure_kind, structures in pairs(old_bc:get_all_structures()) do
      for _, entry in pairs(structures) do
         local data = template_utils._legacy_structure_to_data(building_id, structure_kind, entry.entity, offset, rotation)
         if structure_kind ~= 'stonehearth:fixture_fabricator' then
            local bp = radiant.entities.create_entity(data:get_uri())
            bp:get('stonehearth:build2:blueprint'):init(data)
            bc:add_blueprint(bp)
            stonehearth.building:add_blueprint(bp)
         else
            fixtures[data:get_bid()] = data
         end
      end
   end
   radiant.entities.destroy_entity(old_building)

   -- Fixtures must come after host structures.
   for _, data in pairs(fixtures) do
      local bp = radiant.entities.create_entity(data:get_uri())
      bp:get('stonehearth:build2:blueprint'):init(data)
      bc:add_blueprint(bp)
      stonehearth.building:add_blueprint(bp)
   end

   if rotation and rotation ~= 0 then
      for _, bp in bc:get_blueprints():each() do
         local data = bp:get('stonehearth:build2:blueprint'):get_data()
         data:dangerous_rotate(rot_point, rotation)
      end
   end

   local bids = {}
   for _, bp in bc:get_blueprints():each() do
      local data = bp:get('stonehearth:build2:blueprint'):get_data()
      bids[data:get_bid()] = true
   end

   -- Finally, do the deferred building.
   for _, bp in bc:get_blueprints():each() do
      local data = bp:get('stonehearth:build2:blueprint'):get_data()
      bp:get('stonehearth:build2:blueprint'):update_data(data:deferred_build())
   end

   -- Attach fixtures as sensibly as we can.
   for _, bp in bc:get_blueprints():each() do
      local data = bp:get('stonehearth:build2:blueprint'):get_data()
      if data:get_uri() == FixtureData.URI then
         local bounds = fixture_utils.get_bounds_from_uri(data:get_fixture_uri(), data:get_rotation())
         local bounds_w = bounds:translated(data:get_world_origin())
         local support_bounds_w = Region3(bounds_w:duplicate():get_bounds())
         if not data:is_portal() then
            support_bounds_w = support_bounds_w:translated(-data:get_direction()) - Region3(support_bounds_w:get_bounds())
         else
            -- Old buildings have holes where doors/windows should be, which means we can't really tell what this
            -- portal is embedded in without looking around.  So, be cheap, and just look below.
            support_bounds_w = support_bounds_w:translated(Point3(0, -1, 0)) - Region3(support_bounds_w:get_bounds())
         end

         -- Just pick any blueprint that's overlapping our
         -- Just pick any blueprint that's overlapping ours.
         local es = radiant.terrain.get_entities_in_region(support_bounds_w, function(e)
               if e:get('stonehearth:build2:blueprint') then
                  return e:get('stonehearth:build2:blueprint'):get_uri() ~= FixtureData.URI
               end
               return false
            end)
         if not radiant.empty(es) then
            local bp_host = radiant.first(es)
            local bp_data = bp_host:get('stonehearth:build2:blueprint'):get_data()


            data = data:move_to(bp_data:get_bid(), data:get_world_origin() - bp_data:get_world_origin(), data:get_direction())
            bp_data = bp_data:add_fixture(data:get_bid())

            bp:get('stonehearth:build2:blueprint'):update_data(data)
            bp_host:get('stonehearth:build2:blueprint'):update_data(bp_data)
         end
      end
   end

   -- Recompute structure adjacencies/validity
   mutation_utils.recompute_supports(bids)
   for _, bp in bc:get_blueprints():each() do
      local data = stonehearth.building:get_data(bp:get('stonehearth:build2:blueprint'):get_bid())
      bp:get('stonehearth:build2:blueprint'):update_data(data:deferred_build())
   end

   building:get('stonehearth:build2:building'):reset_costs()

   return building:get_id(), false
end


function template_utils.load_template_data(template_id)
   local prefix = '/r/mods'
   if template_id:starts_with(prefix) then
      return radiant.resources.load_json(template_id:sub(prefix:len() + 1, template_id:len()) .. '.json')
   end
   return _radiant.res.get_custom_building_template(template_id)
end

function template_utils.load_template(building, template_id, base_id, offset, rot_point, rotation, ignore_fixture_quality)
   local template = template_utils.load_template_data(template_id)

   if template_utils.get_major_version(template.header.version) > 0 then
      return template_utils.load_template_from_data(building, template_id, base_id, offset, rot_point, rotation, template, ignore_fixture_quality)
   else
      return template_utils.load_legacy_template(building, template_id, base_id, offset, rot_point, rotation, template)
   end
end

function template_utils.load_template_from_data(building, template_id, base_id, offset, rot_point, rotation, template, ignore_fixture_quality)
   local fixtures = {}

   local bc = building:get('stonehearth:build2:building')

   -- Generate a new template id, so that (once placed), changing this building doesn't
   -- modify the original template.
   bc:set_template_id(_radiant.sim.generate_uuid())
   bc:set_revision(1)
   bc:set_template_icon(template.header.preview_image)

   if template.header.custom_name then
      radiant.entities.set_custom_name(building, template.header.custom_name)
   end

   template.header.sunk = template.header.sunk ~= nil and template.header.sunk or false

   if not template.data then
      return building:get_id(), false
   end

   local bidmap = _bidmap_from_json(template.data, base_id)

   stonehearth.building:set_next_bid(radiant.size(bidmap) + base_id + 1)

   local building_id = building:get_id()
   for _, json in pairs(template.data) do
      local bp = _json_to_blueprint(json, fixtures, building_id, bidmap, offset)

      if bp then
         bc:add_blueprint(bp)
         stonehearth.building:add_blueprint(bp)
      end
   end

   -- Fixtures must come after host structures.
   for _, data in pairs(fixtures) do
      -- ACE: adjust fixture quality
      local f_data = data
      if data:get_quality() == 1 or (ignore_fixture_quality and data:get_quality() ~= -1) then
         log:debug('loading template data and replacing quality %s on fixture %s with -1', data:get_quality(), data:get_uri())
         f_data = data:set_quality(-1)
      end
      local bp = radiant.entities.create_entity(f_data:get_uri())
      bp:get('stonehearth:build2:blueprint'):init(f_data)
      bc:add_blueprint(bp)
      stonehearth.building:add_blueprint(bp)
   end

   -- Finally, do the rotation fixup (now that we can do our data lookups)

   if rotation and rotation ~= 0 then
      for _, bp in bc:get_blueprints():each() do
         local data = bp:get('stonehearth:build2:blueprint'):get_data()
         data:dangerous_rotate(rot_point, rotation)
      end
   end

   -- For giggles, lets do a transitivity inspection here.
   for _, bp in bc:get_blueprints():each() do
      local data = bp:get('stonehearth:build2:blueprint'):get_data()
      local bid = data:get_bid()

      for other_bid, _ in pairs(data:get_supports()) do
         if not stonehearth.building:has_data(other_bid) then
            data.supports[other_bid] = nil
         else
            local other = stonehearth.building:get_data(other_bid)
            if not (other:get_supported()[bid]) then
               log:error('supports transitivity error: %s -> %s', bid, other_bid)
               data.supports[other_bid] = nil
            end
         end
      end

      for other_bid, _ in pairs(data:get_supported()) do
         if not stonehearth.building:has_data(other_bid) then
            data.supported[other_bid] = nil
         else
            local other = stonehearth.building:get_data(other_bid)
            if not (other:get_supports()[bid]) then
               log:error('supported transitivity error: %s -> %s', bid, other_bid)
               data.supported[other_bid] = nil
            end
         end
      end

      for other_bid, _ in pairs(data:get_masks()) do
         if not stonehearth.building:has_data(other_bid) then
            data.masks[other_bid] = nil
         else
            local other = stonehearth.building:get_data(other_bid)
            if not (other:get_masked()[bid]) then
               log:error('masks transitivity error: %s -> %s', bid, other_bid)
               data.masks[other_bid] = nil
            end
         end
      end

      for other_bid, _ in pairs(data:get_masked()) do
         if not stonehearth.building:has_data(other_bid) then
            data.masked[other_bid] = nil
         else
            local other = stonehearth.building:get_data(other_bid)
            if not (other:get_masks()[bid]) then
               log:error('masked transitivity error: %s -> %s', bid, other_bid)
               data.masked[other_bid] = nil
            end
         end
      end

      for other_bid, _ in pairs(data:get_adjacent()) do
         if not stonehearth.building:has_data(other_bid) then
            data.adjacent[other_bid] = nil
         else
            local other = stonehearth.building:get_data(other_bid)
            if not (other:get_adjacent()[bid]) then
               log:error('adjacent transitivity error: %s -> %s', bid, other_bid)
               data.adjacent[other_bid] = nil
            end
         end
      end
   end

   -- Finally, do the deferred building.
   for _, bp in bc:get_blueprints():each() do
      local data = bp:get('stonehearth:build2:blueprint'):get_data()
      bp:get('stonehearth:build2:blueprint'):update_data(data:deferred_build())
   end

   building:get('stonehearth:build2:building'):reset_costs()

   return building:get_id(), template.header.sunk
end

function template_utils.save_building_template_screenshot(building, template_name, done_cb)

   local function create_offscreen_building(building)
      local function create_structure(d, owner)
         local structure = radiant.entities.create_entity('stonehearth:build2:entities:temp_structure', { owner = owner })
         local wr = d:get_world_real_region()
         radiant.terrain.place_entity_at_exact_location(structure, Point3(0, 0, 0), {root_entity = owner})
         structure:get('destination'):get_region():modify(function(cursor)
               cursor:copy_region(wr)
            end)
         -- TODO: ugh, fix this when we get proper ownership.
         if d.get_wall_map then
            for _, walls in d:get_wall_map():each() do
               for _, wall in pairs(walls) do
                  create_structure(wall, owner)
               end
            end
         end
      end

      local offscreen_building = radiant.entities.create_entity('stonehearth:build2:entities:temp_building')

      for _, bp in building:get('stonehearth:build2:building'):get_blueprints():each() do
         local d = bp:get('stonehearth:build2:blueprint'):get_data()
         if d:get_uri() == FixtureData.URI then
            local f = radiant.entities.create_entity(d:get_fixture_uri(), {
               owner = offscreen_building })
            radiant.terrain.place_entity_at_exact_location(f, d:get_world_origin(), {
                  root_entity = offscreen_building,
                  force_iconic = false,
               })
            radiant.entities.turn_to(f, d:get_rotation())
         else
            create_structure(d, offscreen_building)
         end
      end

      return offscreen_building
   end

   local function position_camera(camera, camera_direction, bounds)
      local center = (bounds.min + bounds.max):scaled(0.5)
      local girth = (bounds.max - bounds.min):length()

      local camera_distance = girth * 1.6
      local camera_offset = camera_direction:scaled(camera_distance)
      local position = center + camera_offset

      camera:set_is_orthographic(false)
      camera:set_position(position)
      camera:look_at(center)
      camera:set_fov(35)
   end


   local function get_camera_and_light(cam_pos, world_bounds)
      -- Woo, awful code!  The idea behind this: we don't know what the 'front' of the building
      -- is, so we leave it up to the user, but we constrain the kind of picture we take.  So,
      -- figure out what quadrant around the building the are in (front/back/left/right, or the diagonals.)

      -- These are 'hand-crafted' vectors of camera/light directions for each face of the building.
      local props = {
         {
            camera_direction = Point3(3, 2, -4),
            light_direction = Point3(-50, 140, 0)
         },
         {
            camera_direction = Point3(-3, 2, 4),
            light_direction = Point3(220, 180, 0)
         },
         {
            camera_direction = Point3(-4, 2, -3),
            light_direction = Point3(210, 90, 0)
         },
         {
            camera_direction = Point3(4, 2, 3),
            light_direction = Point3(-50, 90, 0)
         }
      }

      local p = props[1]

      local x_quad = 0
      if cam_pos.x > world_bounds.min.x then
         if cam_pos.x <= world_bounds.max.x then
            x_quad = 0
         else
            x_quad = 1
         end
      else
         x_quad = -1
      end
      local z_quad = 0
      if cam_pos.z > world_bounds.min.z then
         if cam_pos.z <= world_bounds.max.z then
            z_quad = 0
         else
            z_quad = 1
         end
      else
         z_quad = -1
      end

      -- These four cases are the simple ones, where if you're clearly at one side of the building
      -- you just take the picture from that side.
      if x_quad == 0 then
         if z_quad == -1 then
            p = props[1]
         elseif z_quad == 1 then
            p = props[2]
         end
      elseif z_quad == 0 then
         if x_quad == -1 then
            p = props[3]
         elseif x_quad == 1 then
            p = props[4]
         end
      else
         -- These are the awkward cases, where you're at one of the diagonal quadrants.  Figure out
         -- what edge of the quadrant you're closest to, in order to select the appropriate face
         -- of the building from which to take a picture.
         if z_quad == 1 then
            if x_quad == 1 then
               if cam_pos.x - world_bounds.max.x > cam_pos.z - world_bounds.max.z then
                  p = props[4]
               else
                  p = props[2]
               end
            else
               if world_bounds.min.x - cam_pos.x > cam_pos.z - world_bounds.max.z then
                  p = props[3]
               else
                  p = props[2]
               end
            end
         else
            if x_quad == 1 then
               if cam_pos.x - world_bounds.max.x > world_bounds.min.z - cam_pos.z then
                  p = props[4]
               else
                  p = props[1]
               end
            else
               if world_bounds.min.x - cam_pos.x > world_bounds.min.z - cam_pos.z then
                  p = props[3]
               else
                  p = props[1]
               end
            end
         end
      end

      p.camera_direction:normalize()
      return p.camera_direction, p.light_direction
   end

   local bounds_w = building:get('stonehearth:build2:building'):get_blueprint_bounds()

   if bounds_w:get_area() == 0 then
      done_cb()
      return
   end

   local camera_direction, light_direction = get_camera_and_light(
      stonehearth.camera:get_position(),
      bounds_w)

   local offscreen_building = create_offscreen_building(building)
   local building_render_entity, light

   _radiant.client.render_staged_scene(800, function(scene_root, camera)
         building_render_entity = _radiant.client.create_render_entity(scene_root, offscreen_building)

         position_camera(camera, camera_direction, bounds_w)

         light = scene_root:add_directional_light('fake sun')
         light:set_radius_2(10000)
         light:set_fov(360)
         light:set_shadow_map_count(4)
         light:set_shadow_split_lambda(0.95)
         light:set_shadow_map_bias(0.001)
         light:set_color(Point3(0.75, 0.66, 0.75))
         light:set_ambient_color(Point3(0.35,  0.35, 0.35))
         light:set_transform(0, 0, 0, light_direction.x, light_direction.y, light_direction.z, 1, 1, 1)
      end, function()
         if building_render_entity then
            building_render_entity:destroy()
            building_render_entity = nil
         end
         if light then
            light:destroy()
            light = nil
         end
         if offscreen_building then
            radiant.entities.destroy_entity(offscreen_building)
            offscreen_building = nil
         end
      end, function(bytes)
         local template_path =  'building_templates/'.. template_name
         local image_name = 'stonehearth/' .. template_path
         _radiant.client.save_offscreen_image(image_name, bytes)

         local template = _radiant.res.get_custom_building_template(template_name)
         template.header.preview_image = '/r/saved_objects/stonehearth/building_templates/' .. template_name .. '.png'
         _radiant.res.write_custom_building_template(template_name, template)

         if done_cb then
            done_cb()
         end
      end)
end


return template_utils
