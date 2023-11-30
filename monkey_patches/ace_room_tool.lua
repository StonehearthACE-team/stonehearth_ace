local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Point2 = _radiant.csg.Point2
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Ray3 = _radiant.csg.Ray3

local RoomData = require 'stonehearth.lib.building.room_data'
local RoomTool = require 'stonehearth.services.client.building.room_tool'
local AceRoomTool = class()

local log = radiant.log.create_logger('room_tool')

local DEF_WALL_HEIGHT = 6
local TERRAIN_WALL_HEIGHT = 4

function AceRoomTool:_on_start_placing(start_pos)
   log:debug('_on_start_placing(%s)', start_pos)
   -- ACE: if the start position is inside the terrain, make that the top corner of the room instead of the bottom
   -- also make it default to mine height (4)
   self._wall_height = DEF_WALL_HEIGHT
   if radiant.terrain.is_terrain(start_pos) then
      self._wall_height = TERRAIN_WALL_HEIGHT
      start_pos = start_pos - Point3(0, self._wall_height + 1, 0)
      log:debug('making room inside terrain at %s with wall height: %s', start_pos, self._wall_height)
   end
   
   local start_y = start_pos.y
   self._current_building_id = stonehearth.building:get_current_building_id()

   return RoomData.Make(
      self._current_building_id,
      stonehearth.building:get_next_bid(),
      start_pos,
      start_pos + Point3(1, 0, 1),
      self._wall_brush,
      self._column_brush,
      self._floor_brush,
      false,
      self._wall_height), start_pos
end

function AceRoomTool:_on_dragging(start_pos, end_pos, bid)
   local size = radiant.math.abs_point3(end_pos - start_pos)
   if size.x < 1 or size.z < 1 then
      return nil
   end

   if self._unioning then
      local terrain_cube = Cube3(start_pos)
      terrain_cube:grow(end_pos + Point3(0, self._wall_height, 0))
      local rooms = radiant.terrain.get_entities_in_cube(terrain_cube, function(e)
            return e:get('stonehearth:build2:blueprint') ~= nil and
               e:get('stonehearth:build2:blueprint'):get_bid() ~= bid and
               e:get('stonehearth:build2:blueprint'):get_uri() == RoomData.URI

         end)
      self._is_fusing = not radiant.empty(rooms)
   end

   local room_data = RoomData.Make(
      self._current_building_id,
      bid,
      start_pos,
      end_pos,
      self._wall_brush,
      self._column_brush,
      self._floor_brush,
      self._is_fusing,
      self._wall_height)

   return room_data
end

function AceRoomTool:_on_commit(start_pos, end_pos)
   local size = radiant.math.abs_point3(end_pos - start_pos)
   if size.x < 1 or size.z < 1 then
      return nil
   end
   stonehearth.building:add_room(start_pos, end_pos, self._wall_brush, self._column_brush, self._floor_brush, self._is_fusing, self._wall_height)
end

return AceRoomTool
