local TransitionToLookFromController = class()

function TransitionToLookFromController:initialize()
   self.elapsed_time = 0
   self.travel_time = 0
   self.start_rot = nil
   self.end_pos = nil
   self.start_rot = nil
   self.end_rot = nil
end

function TransitionToLookFromController:reinitialize()
   -- Nothing at the moment, if you want to reset data after a higher controller
   -- has been popped making this the top camera controller, do so here
end

function TransitionToLookFromController:create(end_pos, end_rot, travel_time)
   self.elapsed_time = 0
   self.travel_time = travel_time

   self.start_pos = stonehearth.camera:get_position()
   self.end_pos = end_pos

   self.start_rot = stonehearth.camera:get_orientation()
   self.end_rot = end_rot
end

function TransitionToLookFromController:enable_camera(enabled)
   -- Ignore; we don't care whether or not we get disabled.
end

function TransitionToLookFromController:set_position(pos)
   -- Ignore; we don't care what higher level controllers do.
end

function TransitionToLookFromController:set_orientation(pos)
   -- Ignore; we don't care what higher level controllers do.
end

function TransitionToLookFromController:look_at(where)
   -- Ignore; we don't care what higher level controllers do.
end

function TransitionToLookFromController:update(frame_time)
   self.elapsed_time = self.elapsed_time + frame_time
   local t = self.elapsed_time / self.travel_time
   local smooth_t = t * t * (3 - 2 * t)  -- smoothstep

   local pos = self.start_pos:lerp(self.end_pos, smooth_t)
   local rot = self.start_rot:lerp(self.end_rot, smooth_t)
   rot:normalize()

   radiant.events.trigger_async(stonehearth.camera, 'stonehearth:camera:update')

   -- If we're at the end of the lerp, pop ourselves!
   if pos:distance_to(self.end_pos) < 0.1 or t >= 1 then
      stonehearth.camera:pop_controller()
      stonehearth.camera:set_position(self.end_pos)
      stonehearth.camera:set_orientation(self.end_rot)
   end

   return pos, rot
end

return TransitionToLookFromController
