-- not sure if/how to monkey-patch a compound action, so we're just overriding the whole thing :-\

local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local MoveToTargetableLocation = radiant.class()

local log = radiant.log.create_logger('move_to_targetable_location')

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

   local target_location = radiant.entities.get_world_location(target)
   if not target_location then
      return nil
   end

   local range = stonehearth.combat:get_weapon_range(entity, weapon)
   local entity_location = radiant.entities.get_world_location(entity)

   local leash = stonehearth.combat:get_leash_data(entity) or {}

   local center, movement_range = leash.center, leash.range
   if not center then
      center = entity_location
      movement_range = stonehearth.terrain:get_sight_radius()
   end

   local checked = {}
   local max_height = 5
   local search_cube = self:_get_search_cube(entity, center, movement_range, max_height)
   --log:debug('%s search cube %s', entity, search_cube)
   local supported_region = _physics:get_supported_region(Region3(search_cube:extruded('y', 1, 0)), 0):translated(Point3.unit_y)
   local bounds = supported_region:get_bounds()
   --log:debug('%s supported region bounds %s area %s', entity, bounds, supported_region:get_area())
   local slice = Cube3(bounds.min, Point3(bounds.max.x, bounds.min.y + 1, bounds.max.z))
   for y = max_height, 0, -1 do
      local check_region = supported_region:intersect_region(Region3(slice:translated(Point3(0, y, 0))))
      if not check_region:empty() then
         --log:debug('%s check region for y %s: %s', entity, y, check_region:get_bounds())
         local end_point = check_region:get_closest_point(target_location)
         local key = tostring(end_point:to_int())
         if not checked[key] then
            checked[key] = true
            --log:debug('%s trying to get from %s to %s', entity, entity_location, end_point)
            local candidate_location = radiant.terrain.get_direct_path_end_point(entity_location, end_point, entity, true)
            --log:debug('%s considering candidate_location %s', entity, candidate_location)
            if stonehearth.combat:location_in_range(candidate_location, target_location, range) and
                  stonehearth.combat:has_potential_line_of_sight(entity, target, candidate_location, target_location) then
               log:debug('found good attack point %s to attack enemy %s at %s', candidate_location, target, target_location)
               return candidate_location
            end
         end
      end
   end

   return nil
end

function MoveToTargetableLocation:_get_search_cube(entity, center, range, height)
   local search_cube = Cube3(center):inflated(Point3(range, 0, range)):extruded('y', 0, height)
   return search_cube
end

local ai = stonehearth.ai
return ai:create_compound_action(MoveToTargetableLocation)
         :execute('stonehearth:goto_location', {
            reason = 'move to line of sight',
            location = ai.PREV.location,
            grid_location_changed_cb = ai.PREV.grid_location_changed_cb,
         })
