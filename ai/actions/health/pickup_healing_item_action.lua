local Entity = _radiant.om.Entity

local PickupHealingItem = radiant.class()

PickupHealingItem.name = 'pickup healing item'
PickupHealingItem.does = 'stonehearth_ace:pickup_healing_item'
PickupHealingItem.args = {
   target = Entity,
}
PickupHealingItem.think_output = {
   item = Entity,            -- what was actually picked up
}
PickupHealingItem.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PickupHealingItem)
         :execute('stonehearth_ace:find_healing_item', {
            target = ai.ARGS.target,
         })
         :execute('stonehearth:pickup_item', {
            item = ai.PREV.item,
         })
         :set_think_output({
            item = ai.BACK(2).item
         })
