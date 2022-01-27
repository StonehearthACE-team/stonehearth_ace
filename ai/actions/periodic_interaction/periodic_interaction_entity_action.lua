local Entity = _radiant.om.Entity
local InteractWithItem = radiant.class()

InteractWithItem.name = 'periodic_interaction'
InteractWithItem.does = 'stonehearth_ace:periodic_interaction_entity'
InteractWithItem.args = {
   item = Entity,
}
InteractWithItem.priority = 1.0

local log = radiant.log.create_logger('periodic_interaction_entity_action')

local ai = stonehearth.ai
return ai:create_compound_action(InteractWithItem)
         :execute('stonehearth:reserve_entity', {
            entity = ai.ARGS.item
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.ARGS.item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth_ace:periodic_interaction_adjacent', {
            item = ai.ARGS.item
         })