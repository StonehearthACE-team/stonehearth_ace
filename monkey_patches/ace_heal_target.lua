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
   healing_lib.cure_conditions(target_entity, consumable_data.cures_conditions)
	
	-- then treat the basic, level 1 wounds defined in the constants if any is left
   -- local buffs_component = target_entity:get_component('stonehearth:buffs')
	-- if buffs_component then
   --    for basic_condition, _ in pairs(stonehearth.constants.healing.BASIC_CONDITIONS) do
   --       buffs_component:remove_category_buffs(basic_condition, 1)
   --    end
   -- end
	
	-- finally, apply any buffs that the consumable might apply
	if consumable_data.applies_effects then
		for effect, chance in pairs(consumable_data.applies_effects) do
			if rng:get_real(0, 1) < chance then
				radiant.entities.add_buff(target_entity, effect, {
               source = user,
               source_player = radiant.entities.get_player_id(user),
            })
			end  
		end
	end

   healing_lib.heal_target(user, target_entity, consumable_data.health_healed, consumable_data.guts_healed)

   return true
end

return AceHealTarget
