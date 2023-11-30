local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Entity = _radiant.om.Entity
local PolygonBuilder = _radiant.csg.PolygonBuilder

local BuildingData = require 'stonehearth.lib.building.building_data'
local WallMap = require 'stonehearth.lib.building.wall_map'

local log = radiant.log.create_logger('room_data')

local RoomData = require 'stonehearth.lib.building.room_data'
local AceRoomData = class()

local DEF_WALL_HEIGHT = 6
local TERRAIN_WALL_HEIGHT = 4

function AceRoomData.Make(building_id, bid, p1, p2, wall_brush, opt_column_brush, floor_brush, fusing, wall_height)
   local perimeter = PolygonBuilder()
      :add_point(p1.xz)
      :add_point(Point2(p2.x, p1.z))
      :add_point(p2.xz)
      :add_point(Point2(p1.x, p2.z))
      :build()
   local bounds = perimeter:get_bounds()
   local origin = Point3(bounds.min.x, p1.y, bounds.min.y)
   perimeter = perimeter:translated(-bounds.min)

   local wall_map = WallMap(bid)
   wall_height = math.max(1, wall_height or DEF_WALL_HEIGHT)
   log:debug('making room at %s with wall height: %s', p1, wall_height)

   local num_edges = perimeter:num_edges()
   for i = 0, num_edges - 2 do
      local edge = perimeter:edge_at(i)
      wall_map:add_wall(building_id, edge.start, edge.fin, 1, wall_height, wall_brush, opt_column_brush)
   end

   return RoomData(building_id, bid, perimeter, wall_map, floor_brush, origin, {}, {}, {}, {}, {}, {}, fusing):deferred_build()
end

return AceRoomData
