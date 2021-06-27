local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('projectile')

local ProjectileComponent = require 'stonehearth.components.projectile.projectile_component'
local AceProjectileComponent = class()

-- added impact_fade_time optional parameter (defaults to 0): wait this time after impact before destroying
-- added impact_effect optional parameter: if specified, runs this effect until it's finished, potentially extending time to destroy projectile entity
function AceProjectileComponent:_load_json_options()
   self._json = radiant.entities.get_json(self) or {}
   self._impact_fade_time = self._json.impact_fade_time or 0
   self._impact_effect = self._json.impact_effect
end

function ProjectileComponent:start()
   if self._gameloop_trace then
      return
   end

   local vector = self:_get_vector_to_target()
   self:_face_direction(vector)
   self:_load_json_options()

   self._gameloop_trace = radiant.on_game_loop('projectile movement', function()
         if not self._target:is_valid() and not self._impacted then
            self:_destroy_gameloop_trace()
            radiant.entities.destroy_entity(self._entity)
            return
         end

         local vector = self:_get_vector_to_target()
         local distance = vector:length()
         local move_distance = self:_get_distance_per_gameloop(self._speed)

         -- projectile moves speed units every gameloop
         if not self._impacted and distance <= move_distance then
            self:_trigger_impact()
         end

         if self._impacted then
            -- if it's already impacted, just move it along with the target
            local rotated_vector = radiant.math.rotate_about_y_axis(vector, self._target_facing - self._impact_facing)
            
            self._mob:move_to(self._target_location)
            self:_face_direction(rotated_vector)
         else
            vector:normalize()
            vector:scale(move_distance)

            local projectile_location = self._mob:get_world_location()
            local new_projectile_location = projectile_location + vector

            self._mob:move_to(new_projectile_location)
            self:_face_direction(vector)
         end
      end)
end

function ProjectileComponent:_trigger_impact()
   -- We want to destroy the projectile on impact, but can't because the we need a valid entity
   -- to deliver the async porjectile_impact event. So, wait for the event to fire and then
   -- destroy the entity on the following gamelooop.
   -- ACE: actually destroy after a fade time (to allow for projectile effects to continue/fade)
   self._impact_trace = stonehearth.combat:set_timer('stonehearth:combat:projectile_impact', self._impact_fade_time, function()
         -- if the impact effect is still going, wait for it to stop before destroying
         local destroy = function()
            self:_destroy_impact_trace()
            self:_destroy_impacted_entity()
         end

         if self._effect and not self._effect:is_finished() then
            self._effect:set_finished_cb(destroy)
         else
            destroy()
         end
      end)

   radiant.events.trigger_async(self._entity, 'stonehearth:combat:projectile_impact')
   self._impacted = true
   self._impact_facing = radiant.entities.get_facing(self._target)

   -- stop generating new particles on effects on next frame (just remove the effects)
   -- need to wait until next frame so it finishes moving the projectile to the target first
   self._stop_effects_trace = radiant.on_game_loop_once('stop non-impact effects', function()
         local effects = self._entity and self._entity:is_valid() and self._entity:get_component('effect_list')
         if effects then
            local effs_to_remove = {}
            for i, eff in effects:each_effect() do
               if not self._effect or eff ~= self._effect._effect then
                  table.insert(effs_to_remove, eff)
               end
            end

            for _, eff in ipairs(effs_to_remove) do
               effects:remove_effect(eff)
            end
         end
         self._stop_effects_trace = nil
      end)

   if self._impact_effect then
      self:_face_direction(self._vector)
      self._effect = radiant.effects.run_effect(self._entity, self._impact_effect)
   end
end

function ProjectileComponent:_destroy_impacted_entity()
   self:_destroy_gameloop_trace()

   self._wait_to_destroy_trace = radiant.on_game_loop_once('destroy projectile', function()
      if self._entity and self._entity:is_valid() then
         radiant.entities.destroy_entity(self._entity)
      end
      self._wait_to_destroy_trace = nil
   end)
end

function AceProjectileComponent:_get_vector_to_target()
   local projectile_location = self._mob:get_world_location()
   if self._target and self._target:is_valid() then
      self._target_location = self._target:add_component('mob'):get_world_location() + self._target_offset
      self._target_facing = radiant.entities.get_facing(self._target)
   end
   local target_point = self._target_location

   local vector = target_point - projectile_location
   if not self._vector or not self._impacted then
      --log:debug('%s updating vector from %s to %s', self._entity, self._vector or 'nil', vector)
      self._vector = vector
   end
   
   return Point3(self._vector)
end

-- how did this get through in vanilla? they were using seconds as if they were game ticks! (off by a factor of 9/1000)
AceProjectileComponent._ace_old_get_estimated_flight_time = ProjectileComponent.get_estimated_flight_time
function AceProjectileComponent:get_estimated_flight_time()
   local seconds = self:_ace_old_get_estimated_flight_time()
   return stonehearth.calendar:realtime_to_game_seconds(seconds)
end

return AceProjectileComponent
