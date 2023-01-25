local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local IntegerGaussianRandom = require 'stonehearth.lib.math.integer_gaussian_random'
local rng = _radiant.math.get_default_rng()
local igRng = IntegerGaussianRandom(rng)

local log = radiant.log.create_logger('meteor_shower_renderer')

local MeteorShowerWeatherRenderer = class()

local SHOOTING_STAR_INTERVAL = {1, 10}  -- Random in range in game minutes
local SHOOTING_STAR_EFFECTS = {
   { uri = 'stonehearth_ace:effects:shooting_star', size = Point3(6, 5, 6), duration = 200 },
   { uri = 'stonehearth_ace:effects:shooting_star_2', size = Point3(6, 5, 6), duration = 200 },
   { uri = 'stonehearth_ace:effects:shooting_star_3', size = Point3(6, 5, 6), duration = 200 },
   { uri = 'stonehearth_ace:effects:shooting_star_4', size = Point3(6, 5, 6), duration = 200 }
}
local WORLD_BOUNDS_DISTANCE = 100

function MeteorShowerWeatherRenderer:initialize()
   self._clock_trace = nil
   self._time_constants = radiant.resources.load_json('/stonehearth/data/calendar/calendar_constants.json')
   self._next_spawn_time = 0    
   self._anchors = {}
   self._pending_render_entities = {}
end

function MeteorShowerWeatherRenderer:destroy()
   if self._clock_trace then
      self._clock_trace:destroy()
      self._clock_trace = nil
   end
   if self._on_re_creation_listener then
      self._on_re_creation_listener:destroy()
      self._on_re_creation_listener = nil
   end
   self:_destroy_anchors(nil, true)
end

function MeteorShowerWeatherRenderer:_destroy_anchors(now, destroy_all)
   while true do
      local anchor = self._anchors[1]
      if not anchor or (not destroy_all and anchor.expiration > now) then
         break
      end
      table.remove(self._anchors, 1)
      self._pending_render_entities[anchor.entity:get_id()] = nil
      log:debug('destroying effect at %s', radiant.entities.get_world_grid_location(anchor.entity))
      radiant.entities.destroy_entity(anchor.entity)
   end
end

function MeteorShowerWeatherRenderer:activate()
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

   self._on_re_creation_listener = radiant.events.listen(radiant, 'radiant:client:render_entities_created', self, self._on_render_entities_created)
end

function MeteorShowerWeatherRenderer:_update_time(now)
   if now >= self._next_spawn_time then
      self:_destroy_anchors(now)
      self:_try_spawn_shooting_star(now)
      self._next_spawn_time = now + rng:get_real(unpack(SHOOTING_STAR_INTERVAL)) * self._time_constants.seconds_per_minute
   end
end

function MeteorShowerWeatherRenderer:_try_spawn_shooting_star(now)
   local effect = SHOOTING_STAR_EFFECTS[rng:get_int(1, #SHOOTING_STAR_EFFECTS)]
   -- instead of spawning over land, we want these effects to happen off in the distance, outside of the world
   local bounds = radiant.terrain.get_terrain_component():get_bounds()

   -- determine side
   local side = rng:get_int(1, 4)
   local x, y, z
   if side == 1 then
      x = rng:get_int(bounds.min.x, bounds.max.x)
      z = bounds.min.z - WORLD_BOUNDS_DISTANCE
   elseif side == 2 then
      x = bounds.min.x - WORLD_BOUNDS_DISTANCE
      z = rng:get_int(bounds.min.z, bounds.max.z)
   elseif side == 3 then
      x = rng:get_int(bounds.min.x, bounds.max.x)
      z = bounds.max.z + WORLD_BOUNDS_DISTANCE
   else
      x = bounds.max.x + WORLD_BOUNDS_DISTANCE
      z = rng:get_int(bounds.min.z, bounds.max.z)
   end
   y = igRng:get_int(bounds.min.y, 150, (150 - bounds.min.y) / 5)

   -- we're outside the world, so assume the location doesn't intersect with terrain or anything
   local location = Point3(x, y, z)
   self:_spawn_shooting_star_at(location, effect, now)
end

function MeteorShowerWeatherRenderer:_spawn_shooting_star_at(location, effect, now)
   local anchor = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'shooting_star effect anchor' })
   local anchor_data = {
      entity = anchor,
      expiration = now + effect.duration,
      effect = effect.uri,
   }
   table.insert(self._anchors, anchor_data)
   self._pending_render_entities[anchor:get_id()] = anchor_data

   radiant.terrain.place_entity_at_exact_location(anchor, location)
   self:_on_render_entities_created()
end

function MeteorShowerWeatherRenderer:_on_render_entities_created()
   local progress = true
   while not radiant.empty(self._pending_render_entities) and progress do
      progress = false
      for id, anchor_data in pairs(self._pending_render_entities) do
         local re = _radiant.client.get_render_entity(anchor_data.entity)
         if re then
            self._pending_render_entities[id] = nil
            log:debug('starting meteor effect at %s (expiration %s)', radiant.entities.get_world_grid_location(anchor_data.entity), anchor_data.expiration)
            re:start_client_only_effect(anchor_data.effect)
            progress = true
         end
      end
   end
end

return MeteorShowerWeatherRenderer
