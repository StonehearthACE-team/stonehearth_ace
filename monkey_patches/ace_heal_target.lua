local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local HealTarget = radiant.mods.require('stonehearth.entities.consumables.scripts.heal_target')
local AceHealTarget = class()

function AceHealTarget.use(consumable, consumable_data, user, target_entity)
   radiant.assert(user, "Unable to use consumable %s because it requires a user and user was nil", consumable)
   radiant.assert(target_entity, "Unable to use consumable %s because it requires a target entity and target entity was nil", consumable)

   local attributes_component = target_entity:get_component('stonehearth:attributes')
   if not attributes_component then
      return false
   end

   -- first "cure" any conditions that this consumable should cure
   local buffs_component = target_entity:get_component('stonehearth:buffs')
   if buffs_component and consumable_data.cures_conditions then
      for condition, cures_it in pairs(consumable_data.cures_conditions) do
         if cures_it then
            -- remove all buffs that have this condition as their category
            buffs_component:remove_category_buffs(condition)
         end
      end
   end

   local current_health = radiant.entities.get_health(target_entity)
   if current_health > 0 then
      local healed_amount = consumable_data.health_healed * healing_lib.get_healing_multiplier(user)

      radiant.entities.modify_health(target_entity, healed_amount)
   else
      local guts_healed = consumable_data.guts_healed or 1
      radiant.entities.modify_resource(target_entity, 'guts', guts_healed)
   end
   return true
end

return AceHealTarget
