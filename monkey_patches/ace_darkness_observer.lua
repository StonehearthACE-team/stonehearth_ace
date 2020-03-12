local constants = require 'stonehearth.constants'
local RaycastLib = require 'stonehearth.ai.lib.raycast_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local AceDarknessObserver = class()

local LIGHT_SCORE = 10
local DARK_SCORE = -10
local UNDERGROUND_RAY = Point3(0, 10, 0)

function AceDarknessObserver:_update()
   if not radiant.entities.exists_in_world(self._sv._entity) then
      -- skip update
      return
   end

   local score

   if self:_is_in_darkness() then
      score = DARK_SCORE
      radiant.events.trigger_async(self._sv._entity, 'stonehearth:status:in_darkness')
   else
      score = LIGHT_SCORE
   end

   radiant.entities.add_thought(self._sv._entity, 'stonehearth:thoughts:darkness', { value = score })
   self:_visualize_darkness(score)
end

return AceDarknessObserver
