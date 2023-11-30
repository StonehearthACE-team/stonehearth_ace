local Point3 = _radiant.csg.Point3
local WallData = require 'stonehearth.lib.building.wall_data'

local WallTool = require 'stonehearth.services.client.building.wall_tool'
local AceWallTool = class()

local log = radiant.log.create_logger('wall_tool')

local DEF_WALL_HEIGHT = 6
local TERRAIN_WALL_HEIGHT = 4

function AceWallTool:_on_start_placing(start_pos)
   -- ACE: if the start position is inside the terrain, make that the top corner of the wall instead of the bottom
   -- if there's already a room there, match the position and height of the room
   local region = stonehearth.building:get_current_building_room_at_point(start_pos)
   if region then
      local bounds = region:get_bounds()
      self._wall_height = bounds.max.y - bounds.min.y - 1
      start_pos = Point3(start_pos.x, bounds.min.y + 1, start_pos.z)
   elseif radiant.terrain.is_terrain(start_pos) then
      self._wall_height = TERRAIN_WALL_HEIGHT
      start_pos = start_pos - Point3(0, self._wall_height, 0)
   end

   self._wall_height = math.max(1, self._wall_height or DEF_WALL_HEIGHT)
   self._current_building_id = stonehearth.building:get_current_building_id()
   self._origin = start_pos

   return WallData.Make(
      self._current_building_id,
      stonehearth.building:get_next_bid(),
      self._origin,
      self._origin,
      self._wall_height,
      self._wall_brush,
      self._column_brush), start_pos
end

function AceWallTool:_on_dragging(start_pos, end_pos, bid)
   if math.abs(start_pos.x - end_pos.x) > math.abs(start_pos.z - end_pos.z) then
      start_pos.z = self._origin.z
      end_pos.z = self._origin.z
   else
      start_pos.x = self._origin.x
      end_pos.x = self._origin.x
   end
   local wall_data = WallData.Make(
      self._current_building_id,
      bid,
      start_pos,
      end_pos,
      self._wall_height,
      self._wall_brush,
      self._column_brush)

   return wall_data
end

function AceWallTool:_on_commit(start_pos, end_pos)
   stonehearth.building:add_wall(
      start_pos,
      end_pos,
      self._wall_height,
      self._wall_brush,
      self._column_brush)
end

return AceWallTool
