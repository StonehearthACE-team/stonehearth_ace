local HealSelf = radiant.class()

HealSelf.name = 'heal self'
HealSelf.status_text_key = 'stonehearth:ai.actions.status_text.healing'
HealSelf.does = 'stonehearth:rest_from_injuries'
HealSelf.args = {}
HealSelf.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(HealSelf)
         :execute('stonehearth_ace:pickup_healing_item', {
            target = ai.ENTITY
         })
         :execute('stonehearth:heal_entity_adjacent', { container = ai.ENTITY, item = ai.PREV.entity })
