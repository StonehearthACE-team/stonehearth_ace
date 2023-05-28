local AssaultContext = require 'services.server.combat.assault_context'
local BatteryContext = require 'services.server.combat.battery_context'

local AceSiegeAttackRanged = class()

function AceSiegeAttackRanged:_shoot(attacker, target, weapon_data)
   if not target:is_valid() then
      return
   end

   local projectile_speed = weapon_data.projectile_speed
   assert(projectile_speed)
   local projectile = self:_create_projectile(attacker, target, projectile_speed, weapon_data.projectile_uri)
   local projectile_component = projectile:add_component('stonehearth:projectile')
   local flight_time = projectile_component:get_estimated_flight_time()
   local impact_time = radiant.gamestate.now() + flight_time

   local assault_context = AssaultContext('melee', attacker, target, impact_time)
   stonehearth.combat:begin_assault(assault_context)

   -- save this because it will live on in the closure after the shot action has completed
   local attack_info = self._attack_info

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

return AceSiegeAttackRanged
