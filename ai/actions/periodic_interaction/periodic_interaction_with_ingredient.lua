local Entity = _radiant.om.Entity
local pi_lib = require 'stonehearth_ace.lib.periodic_interaction.periodic_interaction_lib'
local InteractWithItemWithIngredient = radiant.class()

InteractWithItemWithIngredient.name = 'periodic interaction'
InteractWithItemWithIngredient.does = 'stonehearth_ace:periodic_interaction_with_ingredient'
InteractWithItemWithIngredient.args = {
   item = Entity,
   ingredient = 'table'       -- an ingredient to bring for the interaction
}
InteractWithItemWithIngredient.priority = 0.5

local log = radiant.log.create_logger('periodic_interaction_with_ingredient')

function InteractWithItemWithIngredient:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._item = args.item
   self._started = false
   self._ready = false

   if not self:_rethink() then
      if periodic_interaction_comp then
         self._listeners = pi_lib.create_usability_listeners(entity, self._item, function()
               self:_rethink()
            end)
      end
   end
end

function InteractWithItemWithIngredient:stop_thinking(ai, entity, args)
   if self._listeners then
      for _, listener in ipairs(self._listeners) do
         listener:destroy()
      end
      self._listeners = nil
   end
end

function InteractWithItemWithIngredient:start(ai, entity, args)
   self._started = true
end

function InteractWithItemWithIngredient:_rethink()
   if self._started then
      return
   end

   local periodic_interaction_comp = self._item and self._item:is_valid() and self._item:get_component('stonehearth_ace:periodic_interaction')
   if periodic_interaction_comp and periodic_interaction_comp:is_usable() and periodic_interaction_comp:is_valid_potential_user(self._entity) then
      if not self._ready then
         self._ready = true
         self._ai:set_think_output({})
         return true
      else
         self._ready = false
         self._ai:clear_think_output()
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(InteractWithItemWithIngredient)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:pickup_ingredient', { ingredient = ai.ARGS.ingredient })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.item })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.item })
         :execute('stonehearth_ace:periodic_interaction_adjacent', {
            item = ai.ARGS.item
         })
