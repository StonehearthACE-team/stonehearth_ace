local WeightedSet = require 'lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local MAX_TRIES_TO_SPAWN = 10
local SNARED_BUFF = 'stonehearth:buffs:tentacle_snared'
local STATE = {
   INACTIVE = 'inactive',
   SPAWNING = 'spawning',
   GRABBING = 'grabbing',
   HOLDING = 'holding',
   DYING = 'dying',
}

local AceTentacleTrapSpawnScript = class()

function AceTentacleTrapSpawnScript:start(ctx, data)
   self._sv.ctx = ctx

   --don't bother trying to spawn for a disconnected player
   if not stonehearth.presence:is_player_connected(ctx.player_id) then
      return
   end

   local population = stonehearth.population:get_population(ctx.player_id)
   local citizens = WeightedSet(rng)
   local town_center = stonehearth.town:get_town(ctx.player_id):get_landing_location()
   for _, citizen in population:get_citizens():each() do
      if ((not data.excluded_role or not citizen:get_component('stonehearth:job'):get_roles()[data.excluded_role])
          and not radiant.entities.has_buff(citizen, SNARED_BUFF)) then
         local distance = radiant.entities.distance_between(citizen, town_center)
         citizens:add(citizen, distance * distance)
      end
   end

   local tries_remaining = MAX_TRIES_TO_SPAWN
   while tries_remaining > 0 and not citizens:is_empty() do
      local citizen = citizens:choose_random()
      citizens:remove(citizen)

      local location = radiant.entities.get_world_location(citizen)
      if location then
         self._sv.target = citizen
         radiant.entities.add_buff(self._sv.target, SNARED_BUFF)

         self._sv.tentacle = radiant.entities.create_entity(data.uri, { owner = data.enemy_player_id })
         self._sv.tentacle:add_component('mob'):turn_to(rng:get_int(0,3)*90)
         radiant.entities.add_buff(self._sv.tentacle, 'stonehearth_ace:buffs:invulnerability')
         radiant.terrain.place_entity_at_exact_location(self._sv.tentacle, location)
         ctx[data.ctx_registration_variable] = self._sv.tentacle

         self:_start_state(STATE.SPAWNING)
         return
      end
      tries_remaining = tries_remaining - 1
   end
end

function AceTentacleTrapSpawnScript:_start_state(new_state)
   self._sv.state = new_state

   if not self._death_listener and self._sv.tentacle then
      self._death_listener = radiant.events.listen(self._sv.tentacle, 'stonehearth:expendable_resource_changed:health', function()
            if radiant.entities.get_health(self._sv.tentacle) <= 0 then
               self:_start_state(STATE.DYING)
            end
         end)
   end

   if self._sv.state == STATE.SPAWNING then
      radiant.effects.run_effect(self._sv.tentacle, 'spawn'):set_finished_cb(function()
         self:_start_state(STATE.GRABBING)
      end)
   elseif self._sv.state == STATE.GRABBING then
      local effect = radiant.effects.run_effect(self._sv.tentacle, 'close', nil, function()
            local carry_block = self._sv.tentacle:add_component('stonehearth:carry_block')
            carry_block:set_carrying(self._sv.target)
            self._injected_ai = stonehearth.ai:inject_ai(self._sv.target, { actions = { "stonehearth:actions:be_held_by_tentacle" } })
         end):set_finished_cb(function()
         self:_start_state(STATE.HOLDING)
      end)
   elseif self._sv.state == STATE.HOLDING then
      radiant.entities.remove_buff(self._sv.tentacle, 'stonehearth_ace:buffs:invulnerability')
      self._holding_effect = radiant.effects.run_effect(self._sv.tentacle, 'holding')
   elseif self._sv.state == STATE.DYING then
      radiant.entities.remove_buff(self._sv.target, SNARED_BUFF)
      radiant.entities.drop_carrying_nearby(self._sv.tentacle)
      if self._injected_ai then
         self._injected_ai:destroy()
         self._injected_ai = nil
      end
      if self._death_listener then
         self._death_listener:destroy()
         self._death_listener = nil
      end
      radiant.effects.run_effect(self._sv.tentacle, 'death'):set_finished_cb(function()
         self:_spawn_effect_at(radiant.entities.get_world_location(self._sv.tentacle), 'stonehearth:effects:death')
         if radiant.entities.exists(self._sv.tentacle) then
            radiant.entities.destroy_entity(self._sv.tentacle)
            self._sv.tentacle = nil
         end
         self:_start_state(STATE.INACTIVE)
      end)
   end
end

return AceTentacleTrapSpawnScript
