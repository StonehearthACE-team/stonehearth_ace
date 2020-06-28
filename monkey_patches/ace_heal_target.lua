local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local HealTarget = radiant.mods.require('stonehearth.entities.consumables.scripts.heal_target')
local rng = _radiant.math.get_default_rng()
local AceHealTarget = class()

function AceHealTarget.use(consumable, consumable_data, user, target_entity)
   radiant.assert(user, "Unable to use consumable %s because it requires a user and user was nil", consumable)
   radiant.assert(target_entity, "Unable to use consumable %s because it requires a target entity and target entity was nil", consumable)

   local attributes_component = target_entity:get_component('stonehearth:attributes')
   if not attributes_component then
      return false
   end

	-- First remove any conditions that this consumable should cure
   local buffs_component = target_entity:get_component('stonehearth:buffs')
   if buffs_component and consumable_data.cures_conditions then
      for condition, cures_rank in pairs(consumable_data.cures_conditions) do
         if cures_rank then
            -- remove all buffs that have this condition as their category
            buffs_component:remove_category_buffs(condition, cures_rank, true)
         end
      end
   end
	
	-- then treat the basic, level 1 wounds defined in the constants if any is left
	if buffs_component then
      for basic_condition, _ in pairs(stonehearth.constants.healing.BASIC_CONDITIONS) do
         buffs_component:remove_category_buffs(basic_condition, 1)
      end
   end
	
	-- finally, apply any buffs that the consumable might apply
	if consumable_data.applies_effects then
		for effect, chance in pairs(consumable_data.applies_effects) do
			if rng:get_real(0, 1) < chance then
				radiant.entities.add_buff(target_entity, effect)
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
