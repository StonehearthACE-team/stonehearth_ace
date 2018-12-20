-- not sure if/how to monkey-patch a compound action, so we're just overriding the whole thing :-\

local FollowPath = require 'ai.lib.follow_path'
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local MoveToTargetableLocation = radiant.class()

MoveToTargetableLocation.name = 'move to targetable location'
MoveToTargetableLocation.does = 'stonehearth:combat:move_to_targetable_location'
MoveToTargetableLocation.args = {
   target = Entity,
   grid_location_changed_cb = {  -- triggered as the chasing entity changes grid locations
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
MoveToTargetableLocation.priority = 0

function MoveToTargetableLocation:start_thinking(ai, entity, args)
   self._ready = false
   self._is_thinking = true
   
   self._delay_start_timer = radiant.on_game_loop_once('GetPrimaryTarget start_thinking', function()
         local update_think_output = function()
               self:_update_think_output(ai, entity, args)
            end

         update_think_output()

         self._leash_changed_trace = radiant.events.listen(entity, 'stonehearth:combat_state:leash_changed', update_think_output)

         if not self._ready then
            self._target_location_trace = radiant.entities.trace_grid_location(args.target, 'move to targetable location')
                                             :on_changed(update_think_output)
         end
      end)
end

function MoveToTargetableLocation:_update_think_output(ai, entity, args)
   if not self._is_thinking then
      return
   end

   local clear_think_output = function()
         if self._ready then
            self._destination = nil
            ai:clear_think_output()
            self._ready = false
         end
      end

   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   -- We only think if the target is not targetable.
   -- This prevents unnecessary pathfinding when we can already shoot the target.
   if stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
      clear_think_output()
      return
   end

   local destination = self:_find_location(entity, args.target)
   if not destination then
      clear_think_output()
      return
   end

   if destination ~= self._destination then
      local grid_location_changed_cb = function()
            local weapon = stonehearth.combat:get_main_weapon(entity)
            if not weapon or not weapon:is_valid() then
               return false
            end

            if stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
               local result = true

               if args.grid_location_changed_cb then
                  result = args.grid_location_changed_cb()
               end

               return result
            end

            return false
         end

      -- Clear think output if we have set it before
      clear_think_output()

      self._destination = destination
      self._ready = true

      ai:set_think_output({
            location = destination,
            grid_location_changed_cb = grid_location_changed_cb,
         })
   end
end

function MoveToTargetableLocation:stop_thinking(ai, entity, args)
   self._is_thinking = false
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end
   if self._leash_changed_trace then
      self._leash_changed_trace:destroy()
      self._leash_changed_trace = nil
   end

   if self._target_location_trace then
      self._target_location_trace:destroy()
      self._target_location_trace = nil
   end
end

-- TODO: shoot rays at several angles and perform local search around each end point
function MoveToTargetableLocation:_find_location(entity, target)
   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      return nil
   end

   local range = stonehearth.combat:get_weapon_range(entity, weapon)
   local entity_location = radiant.entities.get_world_grid_location(entity)
   local target_location = radiant.entities.get_world_grid_location(target)

   local leash = stonehearth.combat:get_leash_data(entity) or {}

   local center, max_range = leash.center, leash.range
   if not center then
      center = radiant.entities.get_world_grid_location(entity)
      max_range = stonehearth.terrain:get_sight_radius()
   end

   local checked = {}
   local search_cube = self:_get_search_cube(entity, center, max_range)
   local slice = search_cube:get_face(Point3.unit_y):extruded('y', 4, 0)
   for y = 0, max_range - 1, 5 do
      local search_point = slice:translated(Point3(0, -y, 0)):get_closest_point(target_location)
      local key = search_point:to_int()
      if not checked[key] then
         checked[key] = true
         local end_point = radiant.terrain.get_direct_path_end_point(entity_location, search_point, entity, true)
         local candidate_location = _physics:get_standable_point(entity, end_point)
         radiant.log.write('stonehearth_ace', 5, tostring(entity)..' checking end_point '..tostring(end_point)..' candidate_location '..tostring(candidate_location))
         if candidate_location.y < end_point.y then
            candidate_location = end_point
         end

         if self:_in_range_and_has_line_of_sight(entity, target, candidate_location, target_location, max_range) then
            radiant.log.write('stonehearth_ace', 5, 'found good attack point '..tostring(candidate_location)..' to attack enemy '..tostring(target)..' at '..tostring(target_location))
            return candidate_location
         end
      end
   end

   return nil
--[[
   local end_point = radiant.terrain.get_direct_path_end_point(entity_location, target_location, entity, true)
   local search_cube = self:_get_search_cube(entity, center, max_range)
   local search_point = search_cube:get_closest_point(end_point)
   local candidate_location = _physics:get_standable_point(entity, search_point)

   if self:_in_range_and_has_line_of_sight(entity, target, candidate_location, target_location, max_range) then
      radiant.log.write('stonehearth_ace', 5, 'settling for bad attack point '..tostring(candidate_location)..' to attack enemy at '..tostring(target_location))
      return candidate_location
   end

   return nil
   ]]
end

function MoveToTargetableLocation:_get_search_cube(entity, center, range)
   local search_cube = Cube3(center):inflated(Point3(range, 0, range)):extruded('y', 0, range)
   return search_cube
end

-- This code must match the implementation of combat_service:in_range_and_has_line_of_sight()
-- or we risk having ai spins.
function MoveToTargetableLocation:_in_range_and_has_line_of_sight(attacker, target, attacker_location, target_location, range)
   if attacker_location:distance_to(target_location) <= range then
      if _physics:has_line_of_sight(attacker, target, attacker_location, target_location) then
         return true
      end
   end

   return false
end

local ai = stonehearth.ai
return ai:create_compound_action(MoveToTargetableLocation)
         :execute('stonehearth:goto_location', {
            reason = 'move to line of sight',
            location = ai.PREV.location,
            grid_location_changed_cb = ai.PREV.grid_location_changed_cb,
         })
