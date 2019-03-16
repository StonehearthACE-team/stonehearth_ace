local HealTarget = radiant.mods.require('stonehearth.entities.consumables.scripts.heal_target')
local AceHealTarget = class()

function AceHealTarget.use(consumable, consumable_data, user, target_entity)
   radiant.assert(user, "Unable to use consumable %s because it requires a user and user was nil", consumable)
   radiant.assert(target_entity, "Unable to use consumable %s because it requires a target entity and target entity was nil", consumable)

   local attributes_component = target_entity:get_component('stonehearth:attributes')
   if not attributes_component then
      return false
   end

   local current_health = radiant.entities.get_health(target_entity)
   if current_health > 0 then
      local healed_amount = consumable_data.health_healed

      -- Apply job perks to amount healed
      local job_component = user:get_component('stonehearth:job')
      local job_controller = job_component and job_component:get_curr_job_controller()
      if job_controller and job_controller.get_healing_item_effect_multiplier then
         healed_amount = math.floor(healed_amount * job_controller:get_healing_item_effect_multiplier())
      end

      radiant.entities.modify_health(target_entity, healed_amount)
   else
      local guts_healed = consumable_data.guts_healed or 1
      radiant.entities.modify_resource(target_entity, 'guts', guts_healed)
   end
   return true
end

return AceHealTarget
