local Color4 = _radiant.csg.Color4
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local build_util = require 'stonehearth.lib.build_util'
local StairsData = require 'stonehearth.lib.building.stairs_data'

local DEFAULT_HEIGHT = 5
local DEFAULT_WIDTH = 3
local DEFAULT_STRIDE = 1
local DEFAULT_STYLE = 'block'

local StairsTool = require 'stonehearth.services.client.building.stairs_tool'
local AceStairsTool = class()

local log = radiant.log.create_logger('stairs_tool')

function AceStairsTool:_get_current_building_room_region()
   if not self._current_building_room_region then
      self._current_building_room_region = stonehearth.building:get_current_building_room_region()
   end
   return self._current_building_room_region
end

function AceStairsTool:_on_start(e)
   self._last_on_start = e
   local thing = self:_selection_under_mouse(e.x, e.y, false)

   if not thing then
      stonehearth.debug_shapes:destroy_box(self._boxid)
      return
   end

   local climb_to = thing.brick
   local normal = thing.normal
   climb_to = climb_to + normal

   -- ACE: allow cutting into current building room regions
   local base = build_util.get_stairs_base(climb_to, { valid_terrain_region = self:_get_current_building_room_region() })
   if not base then
      return false
   end

   self._height = (climb_to - base).y + 1

   -- scale either positively or negatively, never 0
   local dir_scalar = Point3()
   dir_scalar.x = normal.x ~= 0 and normal.x or 1
   dir_scalar.y = normal.y ~= 0 and normal.y or 1
   dir_scalar.z = normal.z ~= 0 and normal.z or 1

   -- reverse the normal since the stairs face the thing whose normal is pointing "away" from itself
   if normal.y == 0 then
      self._facing = Point2(-normal.x, -normal.z)
   end

   --  used to adjust the stairs to account for base calculation
   local x_adj = 0
   local z_adj = 1

   -- if climb_to is not base, meaning we have pointed at something that the stairs can "attach" to
   if climb_to ~= base then
      local facing_ns = normal.z ~= 0
      if facing_ns then
         base.x = base.x + (DEFAULT_WIDTH * dir_scalar.x)
         base.z = base.z + (self._height * dir_scalar.z)
         z_adj = 0
         if self._facing == StairsData.SOUTH then
            z_adj = 1
         end
      else
         base.x = base.x + (self._height * dir_scalar.x)
         base.z = base.z - (DEFAULT_WIDTH * dir_scalar.z)
         if self._facing == StairsData.EAST then
            x_adj = 1
         end
      end
   else
      -- if we are on the ground, move the 'climb_to' forward and deeper, so we build out a box
      -- TODO: I think this is causing complications when we climb_to a 1-high wall. Probably need
      --       to either be smarter or special case
      climb_to.y = climb_to.y + (DEFAULT_HEIGHT * dir_scalar.y)
      if self._facing == StairsData.NORTH or self._facing == StairsData.SOUTH then
         climb_to.x = climb_to.x + (DEFAULT_WIDTH * dir_scalar.x)
         climb_to.z = climb_to.z - (DEFAULT_HEIGHT * dir_scalar.z)
      else
         climb_to.x = climb_to.x + (DEFAULT_HEIGHT * dir_scalar.x)
         climb_to.z = climb_to.z - (DEFAULT_WIDTH * dir_scalar.z)
      end

      -- since we have adjusted climb_to, we need to recalculate height
      self._height = (climb_to - base).y + 1
   end

   -- set values to be used on commit
   self._start_pos = Point3(base.x + x_adj, base.y, base.z + z_adj)
   self._end_pos = Point3(climb_to.x + x_adj, base.y, climb_to.z + z_adj)

   local c = StairsData.compute_collision_shape(self._facing, self._height, base.xz, climb_to.xz, DEFAULT_STRIDE, self._style):translated(Point3(x_adj, base.y, z_adj))

   self:_update_rulers(c, base.y)
   self._boxid = stonehearth.debug_shapes:show_box(c, Color4(0, 255, 0, 255), nil, { box_id = self._boxid })
end

return AceStairsTool
