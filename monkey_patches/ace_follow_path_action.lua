local build_util = require 'stonehearth.lib.build_util'
local FollowPath = require 'stonehearth.ai.lib.follow_path'
local Path = _radiant.sim.Path
local log = radiant.log.create_logger('follow_path')
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local exists_in_world = radiant.entities.exists_in_world
local get_parent = radiant.entities.get_parent
local get_root_entity = radiant.entities.get_root_entity
local get_world_speed = radiant.entities.get_world_speed
local get_posture = radiant.entities.get_posture

--local FollowPathAction = require 'stonehearth.ai.actions.follow_path_action'
local AceFollowPathAction = class()

local MAX_SIGNIFICANT_PATH_LENGTH = 1000  -- All distances above this are insignificant.

function AceFollowPathAction:run(ai, entity, args)
   local parent = get_parent(entity)

   if parent ~= get_root_entity() then
      local mount_component = parent and parent:get_component('stonehearth:mount')
      local user = mount_component and mount_component:get_user()
      if entity == user then
         log:error('%s auto dismounting from %s', entity, parent)
         mount_component:dismount()
      else
         log:error('%s cannot follow path because it is not a child of the root entity; parent = %s', tostring(entity), tostring(parent))
         ai:abort('cannot follow path because entity is not a child of the root entity')
      end
   end

   local path = args.path

   log:detail('following path: %s', path)
   if path:is_empty() then
      log:detail('path is empty. returning')
      return
   end

   local pathfinder_component = entity:add_component('stonehearth:pathfinder')
   local speed = get_world_speed(entity)
   local arrived = false
   self._is_suspended = false

   local arrived_fn = function()
      arrived = true
      if self._is_suspended then
         self._is_suspended = false
         ai:resume('mover finished')
      end
   end

   local aborted_fn = function(message)
      log:detail('mover aborted (path may no longer be traversable)')
      ai:abort('follow_path mover aborted reason: ' .. tostring(message))
   end

   local unstick_cb = function()
      stonehearth.physics:unstick_entity(entity)
   end

   -- see if the path from prev_point to next_point overlaps a ladder
   local get_ladder_normal = function(prev_point, next_point)
      -- prev_point.y may be > or < next_point.y.  construct_cube3 will work
      -- for either case (the Cube3 constructor will not)
      local cube = _radiant.csg.construct_cube3(prev_point, next_point + Point3(1, 0, 1), 0)
      local entities = radiant.terrain.get_entities_in_cube(cube)
      for id, entity in pairs(entities) do
         local ladder = entity:get_component('stonehearth:ladder')
         if ladder then
            return ladder:get_normal()
         elseif entity:get_component('vertical_pathing_region') then
            -- if there's a vertical_pathing_region component, try to get the normal from the entity's facing
            local rotation = 0
            -- recursively check up until the root entity, adding facing at every step
            while entity and entity ~= radiant.entities.get_root_entity() do
               rotation = rotation + entity:add_component('mob'):get_facing()
               entity = get_parent(entity)
            end

            return build_util.rotation_to_normal(rotation)
         end
      end 
      return false;
   end

   local pursuing_changed_cb = function()
      if self._mover then
         local points = self._mover:get_path_points()
         local index = self._mover:get_current_path_index()
         local stop_index = self._mover:get_stop_index()

         local posture_override = nil
         local last_point, next_point = points[index-1], points[index]

         if next_point and last_point then
            -- if we're moving directly up or down and are standing on a 
            -- ladder, switch our posture to stonehearth:climb_ladder_*
            if next_point.x == last_point.x and
               next_point.z == last_point.z and
               math.abs(next_point.y - last_point.y) == 1 then
               local normal = get_ladder_normal(next_point, last_point)
               if normal then
                  local degrees = build_util.normal_to_rotation(normal:scaled(-1))
                  radiant.entities.turn_to(entity, degrees)
                  if next_point.y > last_point.y then
                     posture_override = 'stonehearth:climb_ladder_up'
                  else
                     posture_override = 'stonehearth:climb_ladder_down'
                  end
               end
            end
         end
         
         if posture_override ~= self._posture_override then
            if self._posture_override then
               self._posture_component:unset_posture(self._posture_override)
            end
            if posture_override then
               self._posture_component:set_posture(posture_override)
            end
            self._posture_override = posture_override
         end
         pathfinder_component:set_current_path(points, index, stop_index)
      end
   end

   self._mover = FollowPath(entity, speed, path)
                     :set_stop_distance(args.stop_distance)
                     :set_arrived_cb(arrived_fn)
                     :set_aborted_cb(aborted_fn)
                     :set_unstick_cb(unstick_cb)
                     :set_pursuing_changed_cb(pursuing_changed_cb)
                     :start()

   pathfinder_component:set_mover(self._mover)

   if args.grid_location_changed_cb then
      -- trace entity location before checking early exit, so that we fire the callback at least once
      self._grid_location_trace = radiant.entities.trace_grid_location(entity, 'chase entity')
         :on_changed(function()
               local stop = args.grid_location_changed_cb()
               if stop then
                  if self._mover then
                     self._mover:stop()
                     log:debug('grid location changed callback requested stop')
                  end
                  arrived_fn()
               end
            end)
         :push_object_state()
   end

   if arrived then
      log:detail('mover finished synchronously because entity is already at destination')
   else
      self._posture = get_posture(entity)
      self._posture_listener = radiant.events.listen(entity, 'stonehearth:posture_changed', self, self._on_posture_changed)

      self._animation_mood = self:_get_animation_mood(entity)
      self._mood_listener = radiant.events.listen(entity, 'stonehearth:mood_changed', self, self._on_mood_changed)

      self._speed_listener = radiant.events.listen(entity, 'stonehearth:attribute_changed:speed', self, self._on_speed_changed)
      self:_start_move_effect()

      pursuing_changed_cb()
      self._is_suspended = true
      ai:suspend('waiting for mover to finish')
   end

   -- stop isn't called until all actions in a compound action finish, so stop the effect here now
   self:stop(ai, entity, args)
end

return AceFollowPathAction
