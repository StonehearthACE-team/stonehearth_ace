local AssaultContext = require 'stonehearth.services.server.combat.assault_context'
local BatteryContext = require 'stonehearth.services.server.combat.battery_context'

local AceAttackRanged = class()

local log = radiant.log.create_logger('attack_ranged_action')

-- function AceAttackRanged:stop_thinking(ai, entity, args)
--    log:debug('%s attack_ranged %s, stopping thinking', entity, args.target)
--    if self._think_timer then
--       log:debug('destroying think timer', entity, args.target)
--       self._think_timer:destroy()
--       self._think_timer = nil
--    end

--    self._attack_types = nil
-- end

-- function AceAttackRanged:start(ai, entity, args)
--    log:debug('%s attack_ranged %s, starting', entity, args.target)
-- end

-- function AceAttackRanged:_choose_attack_action(ai, entity, args)
--    -- probably should pass target in as well
--    self._attack_info = stonehearth.combat:choose_attack_action(entity, self._attack_types)

--    if self._attack_info then
--       log:debug('%s attack_ranged %s, selected attack action %s, setting think output', entity, args.target, self._attack_info.name)
--       ai:set_think_output()
--       log:debug('set think output')
--       return
--    end

--    -- choose_attack_action might have complex logic, so just wait 1 second and try again
--    -- instead of trying to guess which coolodowns to track
--    log:debug('%s attack_ranged %s, setting up timer to wait for cooldown', entity, args.target)
--    self._think_timer = stonehearth.combat:set_timer("AttackRanged waiting for cooldown", 1000, function()
--          log:debug('%s attack_ranged %s _choose_attack_action from timer', entity, args.target)
--          self._think_timer = nil
--          self:_choose_attack_action(ai, entity, args)
--       end)
-- end

-- function AceAttackRanged:run(ai, entity, args)
--    log:debug('%s attack_ranged %s, running', entity, args.target)
--    local target = args.target
--    ai:set_status_text_key('stonehearth:ai.actions.status_text.attack_melee_adjacent', { target = target })

--    if radiant.entities.is_standing_on_ladder(entity) then
--       -- We generally want to prohibit combat on ladders. This case is particularly unfair,
--       -- because the ranged unit can attack, but melee units can't find an adjacent to retaliate.
--       ai:abort('Cannot attack attack while standing on ladder')
--    end

--    -- should be get_ranged_weapon
--    local weapon = stonehearth.combat:get_main_weapon(entity)
--    if not weapon or not weapon:is_valid() then
--       log:warning('%s no longer has a valid weapon', entity)
--       ai:abort('Attacker no longer has a valid weapon')
--    end

--    if not stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
--       ai:abort('Target out of ranged weapon range or not in sight')
--       return
--    end

--    log:debug('not aborting, turning to face target', entity, args.target)
--    radiant.entities.turn_to_face(entity, target)

--    log:debug('starting cooldown')
--    stonehearth.combat:start_cooldown(entity, self._attack_info)

--    log:debug('unprotecting target')
--    -- the target might die when we attack them, so unprotect now!
--    ai:unprotect_argument(target)

--    log:debug('setting up shoot timers')
--    -- time_to_impact on the attack action is a misnomer for ranged attacks
--    -- it's really the time the projectile is launched
--    self._shoot_timers = {}
--    if self._attack_info.impact_times then
--       for _, time in ipairs(self._attack_info.impact_times) do
--          log:debug('adding multi shoot timer at %s', time)
--          self:_add_shoot_timer(entity, target, time)
--       end
--    else
--       log:debug('adding single shoot timer at %s', self._attack_info.time_to_impact)
--       self:_add_shoot_timer(entity, target, self._attack_info.time_to_impact)
--    end

--    log:debug('running attack effect')
--    ai:execute('stonehearth:run_effect', { effect = self._attack_info.effect })
-- end

function AceAttackRanged:_shoot(attacker, target, weapon_data)
   if not target:is_valid() then
      return
   end

   -- save this because it will live on in the closure after the shot action has completed
   local attack_info = self._attack_info

   if attack_info.projectile_uri then
      self._projectile_uri = attack_info.projectile_uri
   end

   local projectile_speed = attack_info.projectile_speed or weapon_data.projectile_speed
   assert(projectile_speed)
   local projectile = self:_create_projectile(attacker, target, projectile_speed, self._projectile_uri)
   local projectile_component = projectile:add_component('stonehearth:projectile')
   local flight_time = projectile_component:get_estimated_flight_time()
   local impact_time = radiant.gamestate.now() + flight_time

   local assault_context = AssaultContext('melee', attacker, target, impact_time)
   stonehearth.combat:begin_assault(assault_context)

   local impact_trace
   impact_trace = radiant.events.listen(projectile, 'stonehearth:combat:projectile_impact', function()
         if projectile:is_valid() and target:is_valid() then
            if not assault_context.target_defending then
               radiant.effects.run_effect(target, 'stonehearth:effects:hit_sparks:hit_effect')
               -- ACE: apply self-buffs before damage is calculated
               stonehearth.combat:apply_buffs(attacker, attacker, attack_info)

               local total_damage = stonehearth.combat:calculate_ranged_damage(attacker, target, attack_info)
               local battery_context = BatteryContext(attacker, target, total_damage)
               stonehearth.combat:inflict_debuffs(attacker, target, attack_info)
               stonehearth.combat:battery(battery_context)
            end
         end

         if assault_context then
            stonehearth.combat:end_assault(assault_context)
            assault_context = nil
         end

         if impact_trace then
            impact_trace:destroy()
            impact_trace = nil
         end
      end)

   local destroy_trace
   destroy_trace = radiant.events.listen(projectile, 'radiant:entity:pre_destroy', function()
         if assault_context then
            stonehearth.combat:end_assault(assault_context)
            assault_context = nil
         end

         if destroy_trace then
            destroy_trace:destroy()
            destroy_trace = nil
         end
      end)
end

return AceAttackRanged
