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

   local score = LIGHT_SCORE

   if self:_is_in_darkness() then
      radiant.events.trigger_async(self._sv._entity, 'stonehearth:status:in_darkness')

      -- only make it a negative score if they're not sleepy; TODO: also check traits?
      -- (not necessarily sleeping; it's fine if it's dark when they want to sleep and are preparing to do so)
      local sleepiness = radiant.entities.get_resource(self._sv._entity, 'sleepiness') or 0
      if sleepiness < stonehearth.constants.darkness.MIN_SLEEPINESS_TO_PREFER_DARKNESS then
         score = DARK_SCORE
      end
   end

   radiant.entities.add_thought(self._sv._entity, 'stonehearth:thoughts:darkness', { value = score })
   self:_visualize_darkness(score)
end

return AceDarknessObserver
