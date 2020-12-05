local Quat = _radiant.csg.Quaternion
local CameraService = require 'stonehearth.services.client.camera.camera_service'
local AceCameraService = class()

local log = radiant.log.create_logger('camera')

-- if the camera is moved/rotated within 1 second of the last time, update the last time
local CAMERA_CACHE_THRESHOLD = 1
local CAMERA_MOVE_DURATION = 0.5
local LAST_CALLED_THRESHOLD = 0.6

function AceCameraService:_ensure_camera_cache()
   if not self._camera_cache then
      self._camera_cache = {}

      -- for some reason this gets double-called; some bug with the input system?
      local last_called = -CAMERA_CACHE_THRESHOLD
      stonehearth.hotkey:register_hotkey('cam:previous', function()
         local cur_time = radiant.get_realtime()
         if not self.camera_disabled and cur_time - last_called > LAST_CALLED_THRESHOLD then
            last_called = cur_time
            self:pop_camera_queue()
         end
         return true
      end)
   end
end

function AceCameraService:_cache_camera()
   self:_ensure_camera_cache()

   local position, orientation = _radiant.renderer.get_camera():get_position(), _radiant.renderer.get_camera():get_orientation()

   local cur_time = radiant.get_realtime()

   if #self._camera_cache > 0 then
      local top = self._camera_cache[#self._camera_cache]
      if cur_time - self._camera_last_cached <= CAMERA_CACHE_THRESHOLD then
         -- if it's within the time threshold for the previous cache entry, just update that entry
         top.position = position
         top.orientation = orientation
         return
      elseif top.position == position and top.orientation == orientation then
         -- if it hasn't changed at all, no need to update the cache
         return
      end
   end

   self._camera_last_cached = cur_time
   table.insert(self._camera_cache,
      {
         position = position,
         orientation = orientation,
      })
end

-- AceCameraService._ace_old__update_camera = CameraService._update_camera
-- function AceCameraService:_update_camera(frame_time_wallclock)
--    if self.camera_disabled then
--       return
--    end
--    self:_ace_old__update_camera(frame_time_wallclock)

--    self:_cache_camera()
-- end

AceCameraService._ace_old_set_position = CameraService.set_position
function AceCameraService:set_position(position)
   self:_ace_old_set_position(position)
   self:_cache_camera()
end

AceCameraService._ace_old_set_orientation = CameraService.set_orientation
function AceCameraService:set_orientation(orientation)
   self:_ace_old_set_orientation(orientation)
   self:_cache_camera()
end

AceCameraService._ace_old_look_at = CameraService.look_at
function AceCameraService:look_at(pos)
   self:_ace_old_look_at(pos)
   self:_cache_camera()
end

function AceCameraService:pop_camera_queue()
   self:_ensure_camera_cache()

   if #self._camera_cache > 1 then
      -- remove the last (current camera position)
      -- also remove the next one, because the camera movement will cause a new cache
      table.remove(self._camera_cache, #self._camera_cache)
      local top = table.remove(self._camera_cache, #self._camera_cache)
      local position = top.position
      local orientation = top.orientation

      log:debug('moving camera back to %s, %s', position, orientation)
      self:push_controller('stonehearth_ace:transition_to_look_from_controller', position, orientation, 1000 * CAMERA_MOVE_DURATION)
   end
end

return AceCameraService
