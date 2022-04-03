local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local AddLoneWanderer = class()

function AddLoneWanderer:initialize()
   self._sv.player_id = nil
   self._sv.ctx = nil
   self._sv.data = nil
   self._sv.searcher = nil
end

function AddLoneWanderer:start(ctx, data)
   self._sv.player_id = ctx.player_id
   self._sv.ctx = ctx
   self._sv.data = data

   self:_find_spawn_location()
end

function AddLoneWanderer:_get_fallback_spawn_location()
   local town_center = stonehearth.town:get_town(self._sv.player_id):get_landing_location()
   -- search from max_y to avoid tunnels
   local max_y = radiant.terrain.get_terrain_component():get_bounds().max.y
   local proposed_location = radiant.terrain.get_point_on_terrain(Point3(town_center.x, max_y, town_center.z))
   local spawn_location, found = radiant.terrain.find_placement_point(proposed_location, 20, 30)
   if not found then
      spawn_location = radiant.terrain.find_placement_point(town_center, 1, 7)
   end
   return spawn_location
end

function AddLoneWanderer:_find_location_callback(op, location)
   if op == 'check_location' then
      return self:_check_location(location)
   elseif op == 'set_location' then
      self:_place_citizen(location)
   elseif op == 'abort' then
      self:_place_citizen(self._fallback_location)
   else
      radiant.error('unknown op "%s" in choose_location_outside_town callback', op)
   end
end

function AddLoneWanderer:_check_location(location)
   local r = stonehearth.terrain:get_sight_radius()
   local sight_radius = Point3(r, r, r)
   local cube = Cube3(location):inflated(sight_radius)
   local entities = radiant.terrain.get_entities_in_cube(cube)

   -- check for anything nearby that might attack the new citizen
   for _, entity in pairs(entities) do
      if entity:get_component('stonehearth:ai') then
         local player_id = radiant.entities.get_player_id(entity)
         if stonehearth.player:are_player_ids_hostile(player_id, self._sv.player_id) then
            return false
         end
      end
   end

   -- Check that it's reachable from the center of town.
   if not _radiant.sim.topology.are_strictly_connected(location, self._fallback_location, 0) then
      return false
   end
   
   return true
end

function AddLoneWanderer:_find_spawn_location()
   self._fallback_location = self:_get_fallback_spawn_location()
   self._sv.searcher = radiant.create_controller('stonehearth:game_master:util:choose_location_outside_town',
                                              64, 128,
                                              radiant.bind(self, '_find_location_callback'),
                                              nil,
                                              self._sv.player_id)
end

function AddLoneWanderer:_create_citizen()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   local citizen = pop:create_new_citizen()

   citizen:add_component('stonehearth:job')
               :promote_to(stonehearth.player:get_default_base_job(self._sv.player_id), { skip_visual_effects = true })

   return citizen
end

function AddLoneWanderer:_place_citizen(location)
   local citizen = self:_create_citizen()
   radiant.terrain.place_entity(citizen, location)

   local town = stonehearth.town:get_town(self._sv.player_id)
   --Give the entity the task to run to the banner
   self._approach_task = citizen:get_component('stonehearth:ai')
                              :get_task_group('stonehearth:task_groups:solo:unit_control')
                                 :create_task('stonehearth:goto_town_center', {town = town})
                                 :once()
                                 :start()

   self:_inform_player(citizen)
   self:_destroy_node()
   --TODO: attach particle effect
end

function AddLoneWanderer:_inform_player(citizen)
   --Send another bulletin with to inform player someone has joined their town
   local title = self._sv.data.title --i18n(stonehearth_ace:data.gm.campaigns.game_events.add_lone_wanderer.bulletin_tile)
   local pop = stonehearth.population:get_population(self._sv.player_id)
   pop:show_notification_for_citizen(citizen, title)
end

function AddLoneWanderer:_destroy_node()
   self:destroy()
   -- Remove ourselves from the lib because we don't need the data
   game_master_lib.destroy_node(self._sv.ctx.encounter, self._sv.ctx.parent_node)
end

function AddLoneWanderer:destroy()
   if self._sv.searcher then
      self._sv.searcher:destroy()
      self._sv.searcher = nil
   end
end


return AddLoneWanderer