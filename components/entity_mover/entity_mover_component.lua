--[[
   More flexible version of the projectile component.
   Allows for the optionally-persistent managed movement of an entity, perpetual or piecemeal, using various/custom functions.
]]

local Quaternion = _radiant.csg.Quaternion
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Entity = _radiant.om.Entity

local EntityMoverComponent = class()

local SECONDS_PER_GAMELOOP = 0.05

function EntityMoverComponent:initialize()
   self._sv._destinations = {}
end

function EntityMoverComponent:restore()
   self._is_restore = true
end

function EntityMoverComponent:activate()
   local mob = self._entity:add_component('mob')
   mob:set_interpolate_movement(true)
   mob:set_ignore_gravity(true)

   self._mob = mob
end

function EntityMoverComponent:post_activate()
   -- if we're restoring, resume persistent movement
   -- if we were non-persistently moving, reset position
   if self._sv._is_moving then
      if self._sv._persistent then
         self:_setup_movement_fn()
         self:_start_movement()
      elseif self._sv._start_location and self._sv._start_rotation then
         self._mob:move_to(self._sv._start_location)
         self._mob:set_rotation(self._sv._start_rotation)
      end
   end
end

function EntityMoverComponent:destroy()
   self:_destroy_mover()
end

function EntityMoverComponent:_destroy_mover()
   if self._gameloop_trace then
      self._gameloop_trace:destroy()
      self._gameloop_trace = nil
   end
   if self._movement_obj then
      self._movement_obj:destroy()
      self._movement_obj = nil
   end
end

function EntityMoverComponent:set_bounds(bounds)
   self._sv._bounds = bounds
   self:_ensure_in_bounds()
   self:_update_mover('bounds', bounds)
   return self
end

function EntityMoverComponent:get_speed()
   return self._sv._speed
end

function EntityMoverComponent:set_speed(speed)
   self._sv._speed = speed
   return self
end

function EntityMoverComponent:get_destinations()
   return self._sv._destinations
end

-- destinations can be points or entities
function EntityMoverComponent:set_destinations(destinations)
   self._sv._destinations = radiant.values(destinations)
   self:_update_mover('destinations', self._sv._destinations)
   return self
end

function EntityMoverComponent:add_destination(destination)
   table.insert(self._sv._destinations, destination)
   self:_update_mover('destinations', self._sv._destinations)
   return self
end

function EntityMoverComponent:hit_destination(destinations)
   local d = table.remove(destinations, 1)
   local sv_destinations = self._sv._destinations
   if destinations ~= sv_destinations and #sv_destinations > 0 then
      -- if we're using a custom destinations list, check the first "real" destination to see if we need to clear it
      local destination = self:_get_destination_point(sv_destinations[1])
      if destination == d then
         table.remove(sv_destinations, 1)
      end
   end
   -- if #self._sv._destinations < 1 then
   --    -- we hit the final destination; moving should finish now
   --    self:_finished_movement()
   -- end
end

function EntityMoverComponent:skip_destination()
   local destinations = self._sv._destinations
   if #destinations > 0 then
      self:hit_destination(destinations)
      self:_update_mover('destinations', destinations)
   end
end

function EntityMoverComponent:set_facing_type(facing_type)
   self._sv._facing_type = facing_type
   return self
end

function EntityMoverComponent:set_movement_type(movement_type, custom_script)
   -- assert(movement_type == stonehearth.constants.entity_mover.movement_types.CUSTOM or not custom_script,
   --        'entity_mover requires a standard movement type or a custom script')

   self._sv._movement_type = movement_type
   self._sv._custom_script = custom_script
   
   -- if we're changing the movement type mid-movement (why?!), reset the movement function
   -- otherwise, it gets set naturally when movement is started
   if self._gameloop_trace then
      self:_setup_movement_fn()
   end
   return self
end

function EntityMoverComponent:start_persistent_movement()
   self._sv._persistent = true
   self._tick_cb = nil
   self._finished_cb = nil
   self:_start_movement()
   return self
end

function EntityMoverComponent:start_nonpersistent_movement(tick_cb, finished_cb)
   self._sv._persistent = false
   -- can only have callback functions on non-persistent movement
   self._tick_cb = tick_cb
   self._finished_cb = finished_cb

   self:_start_movement()
   return self
end

function EntityMoverComponent:_start_movement()
   self:_destroy_mover()
   self:_setup_movement_fn()
   self._sv._start_location = radiant.entities.get_world_location(self._entity)
   self._sv._start_rotation = self._entity:add_component('mob'):get_rotation()

   if #self._sv._destinations > 0 and self._movement_fn and self._sv._speed then
      self._sv._is_moving = true

      self:_update_facing()

      self._gameloop_trace = radiant.on_game_loop('entity_mover movement', function()
         if self._sv._is_moving then
            if not self._movement_fn(self._movement_obj, self) then
               self:_finished_movement()
            end
         end
      end)
   end
end

function EntityMoverComponent:_setup_movement_fn()
   if not self._sv._facing_type then
      self._sv._facing_type = stonehearth.constants.entity_mover.facing_types.NONE
   end
   
   if self._sv._custom_script then
      local script = radiant.mods.load_script(self._sv._custom_script)
      self._movement_obj = script(self._entity, self)
      self._movement_fn = self._movement_obj.move_on_game_loop
   else
      local movement_types = stonehearth.constants.entity_mover.movement_types
      self._movement_obj = nil
      if self._sv._movement_type == movement_types.DIRECT then
         self._movement_fn = function()
            local move_distance = self:_get_distance_per_gameloop(self._sv._speed)
            self:_move_directly(self._sv._destinations, move_distance)
            return #self._sv._destinations > 0
         end
      end
   end
end

function EntityMoverComponent:pause_movement()
   self._sv._is_moving = false
   return self
end

function EntityMoverComponent:resume_movement()
   if self._gameloop_trace then
      self._sv._is_moving = true
   end
   return self
end

function EntityMoverComponent:stop_movement()
   self:_destroy_mover()
   self._sv._is_moving = false
   return self
end

function EntityMoverComponent:_finished_movement()
   self:stop_movement()
   if self._finished_cb then
      self._finished_cb()
   end
   radiant.events.trigger(self._entity, 'stonehearth_ace:entity_mover:finished_movement')
end

function EntityMoverComponent:_ensure_in_bounds()

end

function EntityMoverComponent:_update_mover(field, value)
   if self._movement_obj and self._movement_obj.update then
      self._movement_obj:update(field, value)
   end
end

function EntityMoverComponent:get_estimated_direct_time_to_next_destination()
   local destination = self._sv._destinations[1]
   if destination then
      local vector = self:_get_vector_to_target(self._mob:get_world_location(), destination)
      local distance = vector:length()
      return stonehearth.calendar:realtime_to_game_seconds(distance / self._sv._speed)
   else
      return 0
   end
end

-- speed in blocks/s at normal gamespeed
function EntityMoverComponent:_get_distance_per_gameloop(speed)
   local game_speed = stonehearth.game_speed:get_game_speed()
   local distance = (speed or self._sv._speed) * SECONDS_PER_GAMELOOP * game_speed
   return distance
end

function EntityMoverComponent:_get_destination_point(target)
   if radiant.util.is_a(target, Point3) then
      return target
   elseif radiant.util.is_a(target, Entity) then
      local location = target:add_component('mob'):get_world_location()
      -- maybe also offset to the center of the collision region or something specified in entity_data?
      -- for now just leave it at the ground
      return location
   else
      return target.location
   end
end

function EntityMoverComponent:_get_vector_to_target(location, target)
   return self:_get_destination_point(target) - location
end

function EntityMoverComponent:_move_directly_to_destination(destinations, location, destination, max_distance)
   local vector = self:_get_vector_to_target(location, destination)
   local distance_to = vector:length()
   max_distance = max_distance or distance_to
   local distance = math.min(distance_to, max_distance)

   if distance_to > max_distance then
      vector:normalize()
      vector:scale(distance)
   else
      self:hit_destination(destinations)
   end

   return location + vector, max_distance - distance, vector
end

function EntityMoverComponent:_move_directly(destinations, move_distance)
   local location = self._mob:get_world_location()
   while #destinations > 0 and move_distance > 0 do
      location, move_distance = self:_move_directly_to_destination(destinations, location, destinations[1], move_distance)
   end

   self:_update_facing(location)
   self._mob:move_to(location)
end

function EntityMoverComponent:_update_facing(destination)
   destination = destination or self._sv._destinations[1]
   if destination then
      local facing_types = stonehearth.constants.entity_mover.facing_types
      if self._sv._facing_type == facing_types.FULL then
         self:_face_direction(self:_get_vector_to_target(self._mob:get_world_location(), destination))
      elseif self._sv._facing_type == facing_types.Y_ONLY then
         self._mob:turn_to_face_point(self:_get_destination_point(destination))
      end
   end
end

-- 3-space version of turn_to_face
function EntityMoverComponent:_face_direction(direction)
   local rotation = Quaternion()
   rotation:look_at(Point3.zero, direction)
   self._mob:set_rotation(rotation)
end

return EntityMoverComponent
