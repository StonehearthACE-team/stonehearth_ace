local Entity = _radiant.om.Entity

local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local PickupHealingItem = radiant.class()

PickupHealingItem.name = 'pickup healing item'
PickupHealingItem.does = 'stonehearth_ace:pickup_healing_item'
PickupHealingItem.args = {
   target = Entity,
}
PickupHealingItem.think_output = {
   item = Entity,            -- what was actually picked up
   path_length = {
      type = 'number',
      default = 0,
   },
}
PickupHealingItem.priority = 0

local MIN_GUTS_PERCENTAGE_TO_PREFER = 90

function PickupHealingItem:start_thinking(ai, entity, args)
   self._started = nil
   self._ready = nil
   self._ai = ai
   self._healer = entity
   self._target = args.target

   -- listen for a rethink if the healer's level changes (or the target's status changes?) and the action hasn't started yet
   -- (if the action has already started, maybe they're using a less-than-optimal item, but they're still using something)
   self._level_changed_listener = radiant.events.listen(entity, 'stonehearth:level_up', function()
         self:_rethink()
      end)

   self:_rethink()
end

function PickupHealingItem:start(ai, entity, args)
   self._started = true
end

function PickupHealingItem:_rethink()
   if not self._started then
      if self._ready then
         self._ai:clear_think_output()
      end

      local filter_fn = healing_lib.make_healing_filter(self._healer, self._target)
      if not filter_fn then
         return
      end

      self._ready = true
      self._ai:set_think_output({
         filter_fn = filter_fn,
         rating_fn = healing_lib.make_healing_rater(self._healer, self._target),
      })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupHealingItem)
         :execute('stonehearth:pickup_item_type', {
            description = 'healing_item',
            filter_fn = ai.PREV.filter_fn,
            rating_fn = ai.PREV.rating_fn
         })
         :set_think_output({
            item = ai.PREV.item,
            path_length = ai.PREV.path_length,
         })
