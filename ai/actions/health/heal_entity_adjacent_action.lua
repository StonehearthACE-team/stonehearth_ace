local Entity = _radiant.om.Entity
local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local HealEntityAdjacent = radiant.class()
HealEntityAdjacent.name = 'heal entity adjacent'
HealEntityAdjacent.does = 'stonehearth:heal_entity_adjacent'
HealEntityAdjacent.args = {
   container = Entity,   -- the container the entity is in
   item = Entity,        -- The healing item
}
HealEntityAdjacent.priority = 0

function HealEntityAdjacent:run(ai, entity, args)
   local injured_entity = nil
   if args.container == entity then
      injured_entity = entity
      -- this check is unnecessary because they won't pick this ai action unless they're at least injured or suffering a condition
      -- if radiant.entities.has_buff(entity, 'stonehearth:buffs:injured') or
      --    radiant.entities.has_buff(entity, 'stonehearth:buffs:severely_injured') then
      --       injured_entity = entity
      -- end
   else
      local container_user = args.container:get_component('stonehearth:mount'):get_user()
      if container_user and radiant.entities.has_buff(container_user, 'stonehearth:buffs:hidden:needs_medical_attention') and
            not radiant.entities.has_buff(container_user, 'stonehearth:buffs:recently_treated') then
         injured_entity = container_user
      end
   end

   if not injured_entity then
      ai:abort('no injured entity needs healing')
      return
   end

   ai:set_status_text_key('stonehearth:ai.actions.status_text.healing_target', { target = injured_entity })
   local consumable = args.item
   local consumable_data = radiant.entities.get_entity_data(consumable, 'stonehearth:consumable')

   if not consumable_data then
      radiant.verify(false, "Unable to use consumable %s because it has no entity data for consumables", consumable)
      return
   end

   ai:execute('stonehearth:run_effect', { effect = 'fiddle', times=consumable_data.work_units or 1, facing_entity = consumable })

   if ConsumablesLib.use_consumable(consumable, entity, injured_entity) then
      radiant.events.trigger_async(entity, 'stonehearth:repaired_entity', { entity = injured_entity })
      radiant.events.trigger_async(injured_entity, 'stonehearth:entity:healed', { healer = entity })
      ai:unprotect_argument(consumable)
      radiant.entities.destroy_entity(consumable)
   end
end

return HealEntityAdjacent
