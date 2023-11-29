local build_util = require 'stonehearth.lib.build_util'

local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('build.ladder')
local AceLadderManager = class()

-- ACE: allow force build at 'to', even if 'to' is not normally available
-- xxx: this is only correct in a world where the terrain doesn't change.
-- we should take a pass over all the ladder building code and make sure
-- it can handle cases where the ground around the latter starts moving.
function AceLadderManager:request_ladder_to(owner, to, normal, options)
   checks('self', 'string|Entity', 'Point3', 'Point3', '?table')
   log:detail('%s requesting ladder to %s', owner, to)

   options = options or {}

   log:detail('computing ladder base')
   local base = options.force_build and to or build_util.get_ladder_base(to, options)
   if not base then
      log:detail('ignoring request: destination is not a valid rung position')
      return radiant.create_controller('stonehearth:build:ladder_builder:destructor')
   end

   local min_ladder_height = options.min_ladder_height or 0
   local ladder_height = to.y - base.y + 1
   if ladder_height < min_ladder_height then
      log:detail('ignoring request: ladder is less than minimum requested height')
      return radiant.create_controller('stonehearth:build:ladder_builder:destructor')
   end

   local ladder_builder = self._sv.ladder_builders[base:key_value()]
   if not ladder_builder then
      local id = self:_get_next_id()

      log:detail('creating new ladder builder (lbid:%d)!', id)
      ladder_builder = radiant.create_controller('stonehearth:build:ladder_builder', self, id, owner, base, normal, options)
      self._sv.ladder_builders[base:key_value()] = ladder_builder
      self.__saved_variables:mark_changed()
   end
   log:detail('adding %s to ladder builder (lbid:%d)', to, ladder_builder:get_id())

   local ladder_handle = ladder_builder:add_point(to, options)
   return ladder_handle
end

return AceLadderManager