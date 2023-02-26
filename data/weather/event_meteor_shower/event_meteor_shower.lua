local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local rng = _radiant.math.get_default_rng()

local EventMeteorShowerWeather = class()

local METEORITE_INTERVAL = '120m+350m'
local METEORITE_EFFECTS = {
   'stonehearth_ace:effects:meteorite_effect'
}
local METEORITE_GROUND_EFFECT = 'stonehearth_ace:effects:meteorite_impact_ground'

function EventMeteorShowerWeather:initialize()
   self._sv._meteorite_timer = nil
   self._sv.notification_bulletin = nil
end

function EventMeteorShowerWeather:destroy()
   self:stop()
end

function EventMeteorShowerWeather:start()
   self._sv._meteorite_timer = stonehearth.calendar:set_persistent_timer('event_meteor_shower meteorite', METEORITE_INTERVAL, radiant.bind(self, '_spawn_meteorite'))

   local bulletin_data = {
      title = "i18n(stonehearth_ace:data.weather.event.meteor_shower.bulletin_name)",
      notification_closed_callback = '_on_closed'
   }
   
   local players = stonehearth.player:get_non_npc_players()
   for player_id in pairs(players) do
      self._sv.notification_bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
            :set_callback_instance(self)
            :set_sticky(true)
            :set_data(bulletin_data)
   end
end

function EventMeteorShowerWeather:restore()
   if self._sv._METEORITE_INTERVAL then  -- Old savegames
      self._sv._METEORITE_INTERVAL:destroy()
      self._sv._METEORITE_INTERVAL = nil
   end
end

function EventMeteorShowerWeather:stop()
   if self._sv._meteorite_timer then
      self._sv._meteorite_timer:destroy()
      self._sv._meteorite_timer = nil
   end
   if self._sv.notification_bulletin then
      self._sv.notification_bulletin:destroy()
      self._sv.notification_bulletin = nil
   end
end

function EventMeteorShowerWeather:_spawn_meteorite()
   local effect = METEORITE_EFFECTS[rng:get_int(1, #METEORITE_EFFECTS)]
   local meteorite = radiant.entities.create_entity('stonehearth_ace:resources:starsteel:ore', { owner = '' } )
   meteorite:add_component('stonehearth:commands'):add_command('stonehearth:commands:loot_item')
   -- Choose a point to hit.
   local terrain_bounds = stonehearth.terrain:get_bounds()
   local x = rng:get_int(terrain_bounds.min.x, terrain_bounds.max.x)
   local z = rng:get_int(terrain_bounds.min.z, terrain_bounds.max.z)
   local pt = radiant.terrain.get_point_on_terrain(Point3(x, terrain_bounds.max.y, z))
   local ground_point = radiant.terrain.find_placement_point(pt, 0, 10, meteorite)

   -- Don't hit water.
   local search_cube = Cube3(ground_point - Point3(1, 2, 1),
                             ground_point + Point3(1, 2, 1))
   local is_in_water = next(radiant.terrain.get_entities_in_cube(search_cube, function(e)
                            return e:get_component('stonehearth:water') ~= nil
                            end)) ~= nil
   if not is_in_water then
      ground_point.y = ground_point.y + 1  -- On top of the terain voxel.
      self:_spawn_effect_at(ground_point, effect)
      self:_spawn_effect_at(ground_point, METEORITE_GROUND_EFFECT)

      radiant.terrain.place_entity_at_exact_location(meteorite, ground_point)
   else
      radiant.entities.destroy_entity(meteorite)
   end
   self._sv._meteorite_timer = stonehearth.calendar:set_persistent_timer('event_meteor_shower ligtning', METEORITE_INTERVAL, radiant.bind(self, '_spawn_meteorite'))
end

function EventMeteorShowerWeather:_spawn_effect_at(location, effect)
   local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'event_meteor_shower meteorite effect anchor' })
   radiant.terrain.place_entity_at_exact_location(proxy, location)
   radiant.effects.run_effect(proxy, effect):set_finished_cb(function()
      radiant.entities.destroy_entity(proxy)
   end)
end

return EventMeteorShowerWeather
