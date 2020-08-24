local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local rng = _radiant.math.get_default_rng()

local SandyDriftsWeatherRenderer = class()

local DRIFT_INTERVAL = {1, 3}  -- Random in range in game minutes
local DRIFT_EFFECTS = {
   { uri = 'stonehearth_ace:effects:sandy_drifts:swirl', size = Point3(6, 5, 6) },
   { uri = 'stonehearth_ace:effects:sandy_drifts:breeze', size = Point3(5, 4, 30) },
}
local MAX_POINTS_TO_TRY_PER_SPAWN = 3
local SCREEN_MARGIN = 100

function SandyDriftsWeatherRenderer:initialize()
   self._drift_anchor = nil
   self._clock_trace = nil
   self._time_constants = radiant.resources.load_json('/stonehearth/data/calendar/calendar_constants.json')
   self._next_spawn_time = 0         
end

function SandyDriftsWeatherRenderer:destroy()
   if self._clock_trace then
      self._clock_trace:destroy()
      self._clock_trace = nil
   end
end

function SandyDriftsWeatherRenderer:activate()
   self._drift_anchor = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'drift effect anchor' })
   radiant.terrain.place_entity_at_exact_location(self._drift_anchor, Point3(0, 0, 0))
   
   _radiant.call('stonehearth:get_clock_object'):done(function (o)
         local clock_object = o.clock_object
         self._clock_trace = clock_object:trace_data('drawing sky')
            :on_changed(function()
                  local date = clock_object:get_data()
                  if date then
                     self:_update_time(date.second + (self._time_constants.seconds_per_minute * (date.minute + (self._time_constants.minutes_per_hour * date.hour))))
                  end
               end)
            :push_object_state()
      end)
end

function SandyDriftsWeatherRenderer:_update_time(now)
   if now >= self._next_spawn_time then
      if self:_try_spawn_drift() then
         self._next_spawn_time = now + rng:get_real(unpack(DRIFT_INTERVAL)) * self._time_constants.seconds_per_minute
      end
   end
end

function SandyDriftsWeatherRenderer:_try_spawn_drift()
   local effect = DRIFT_EFFECTS[rng:get_int(1, #DRIFT_EFFECTS)]

   local location
   for _ = 1, MAX_POINTS_TO_TRY_PER_SPAWN do
      -- Select a random spot in the player's view.
      local x = rng:get_int(SCREEN_MARGIN, 1920 - SCREEN_MARGIN)
      local y = rng:get_int(SCREEN_MARGIN, 1080 - SCREEN_MARGIN)
      location = selector_util.get_selected_brick(x, y, function(result)
            if result.normal.y < 0.95 then
               return stonehearth.selection.FILTER_IGNORE  -- Only stop on up-facing voxels.
            else
               if result.entity ~= radiant._root_entity then
                  return stonehearth.selection.FILTER_IGNORE  -- Only look at terrain.
               end

               return true
            end
         end)

      -- Check that we have no obstacles.
      if location then
         -- TODO: Check each effect, rather than choosing one early.
         local search_cube = Cube3(location + Point3(0, 1, 0), location + effect.size)
         for _, entity in pairs(radiant.terrain.get_entities_in_cube(search_cube)) do
            if (entity == radiant._root_entity or
                entity:get_component('stonehearth:construction_data') or
                entity:get_component('stonehearth:build2:structure')) then  -- terrain or buildings
               location = nil
               break
            end
         end
      end

      if location then
         break  -- Found a good one!
      end
   end

   if location then
      return self:_spawn_drift_at(location, effect.uri)
   else
      return false
   end
end

function SandyDriftsWeatherRenderer:_spawn_drift_at(location, effect)
   if not self._drift_anchor then
      return false -- Too early
   end
   
   local render_entity = _radiant.client.get_render_entity(self._drift_anchor)
   if not render_entity then
      return false  -- Too early
   end

   radiant.entities.move_to(self._drift_anchor, location)

   render_entity:start_client_only_effect(effect)
   
   return true
end

return SandyDriftsWeatherRenderer
