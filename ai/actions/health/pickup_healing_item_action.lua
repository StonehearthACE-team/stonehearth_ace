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

function PickupHealingItem:stop_thinking(ai, entity, args)
   if self._level_changed_listener then
      self._level_changed_listener:destroy()
      self._level_changed_listener = nil
   end
   if self._on_game_loop then
      self._on_game_loop:destroy()
      self._on_game_loop = nil
   end
end

function PickupHealingItem:start(ai, entity, args)
   self._started = true
end

function PickupHealingItem:_rethink()
   if not self._started then
      local filter_fn = healing_lib.make_healing_filter(self._healer, self._target)
      if not filter_fn then
         return
      end

      local set_ready = function()
         self._ready = true
         self._ai:set_think_output({
            filter_fn = filter_fn,
            rating_fn = healing_lib.make_healing_rater(self._healer, self._target),
         })
      end

      if self._ready then
         self._ready = nil
         self._ai:clear_think_output()
         -- don't call clear_think_output and set_think_output on the same frame
         self._on_game_loop = radiant.on_game_loop_once('pickup_healing_item_action set_think_output', function()
            self._on_game_loop = nil
            set_ready()
         end)
      else
         set_ready()
      end
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
