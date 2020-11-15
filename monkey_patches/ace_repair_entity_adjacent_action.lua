local AceRepairEntityAdjacent = radiant.class()

-- ACE: override this function to use the craft effect if available instead of only the 'wrench' effect
-- if the target's siege_data contains a repair_effect, that is prioritized; second is the tool's repair_data.repair_effect
-- finally, the crafter component work effect (specified in job description file), or 'wrench' if still nothing has been specified
function AceRepairEntityAdjacent:run(ai, entity, args)
   local target = args.entity
   ai:set_status_text_key('stonehearth:ai.actions.status_text.repair_entity', { target = target })

   -- get work units from siege weaon entity data
   local siege_data = radiant.entities.get_entity_data(target, 'stonehearth:siege_object')
   if not siege_data then
      ai:abort('Target entity is not a siege object')
      return
   end

   local repair_work_units = siege_data.repair_work_units or 1
   local health = radiant.entities.get_health(target)

   local weapon = stonehearth.combat:get_main_weapon(entity)
   local repair_data = radiant.entities.get_entity_data(weapon, 'stonehearth:repair_data') or {}
   --radiant.verify(repair_data, 'repair_data missing from mainhand weapon %s of entity %s who is trying to repair', weapon, entity)
   local base_repair_amount = repair_data and repair_data.base_repair_amount or 1
   local repair_effect = siege_data.repair_effect or repair_data.repair_effect
   if not repair_effect then
      local crafter_comp = entity:get_component('stonehearth:crafter')
      repair_effect = crafter_comp and crafter_comp:get_work_effect() or 'wrench'
   end

   if health ~= nil then
      local repair_amount = self:_calculate_repair_amount(entity, base_repair_amount)
      local health_percentage = radiant.entities.get_health_percentage(target)
      while health_percentage < 1 do
         if radiant.entities.get_health(target) <= 0 then
            ai:abort('Target entity is dead')
            return
         end
         ai:execute('stonehearth:run_effect', { effect = repair_effect, times = repair_work_units, facing_entity = target })
         radiant.entities.modify_health(args.entity, repair_amount)
         radiant.events.trigger_async(entity, 'stonehearth:repaired_entity', {})
         health_percentage = radiant.entities.get_health_percentage(target)
      end
   end

   local siege_weapon_component = target:get_component('stonehearth:siege_weapon')
   if siege_weapon_component then
      local repair_amount = repair_data and repair_data.siege_weapon_repair_amount or 1
      local usage_percentage = siege_weapon_component:get_usage_percentage()
      while usage_percentage < 1 do
         ai:execute('stonehearth:run_effect', { effect = repair_effect, times = repair_work_units, facing_entity = target })
         siege_weapon_component:refill_uses(repair_amount)
         radiant.events.trigger_async(entity, 'stonehearth:repaired_entity', { action = 'refill_ammo' })
         usage_percentage = siege_weapon_component:get_usage_percentage()
      end
   end

   -- reconsider the entity so that the spacial cache can remove it if necessary
   stonehearth.ai:reconsider_entity(target, 'entity fully repaired')
end

return AceRepairEntityAdjacent
