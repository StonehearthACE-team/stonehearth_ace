local BecomeIncapacitated = radiant.class()

BecomeIncapacitated.name = 'become incapacitated'
BecomeIncapacitated.does = 'stonehearth:top'
BecomeIncapacitated.status_text_key = 'stonehearth:ai.actions.status_text.incapacitated'
BecomeIncapacitated.args = {}
BecomeIncapacitated.priority = 0.9

function BecomeIncapacitated:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._became_incapacitated_listener = radiant.events.listen(entity, 'stonehearth:entity:became_incapacitated', self, self._on_became_incapacitated)
end

function BecomeIncapacitated:_on_became_incapacitated()
   -- if they're already in a bed, don't do this version
   local parent = radiant.entities.get_parent(self._entity)
   local bed_data = parent and radiant.entities.get_entity_data(parent, 'stonehearth:bed')
   local mount = parent and parent:get_component('stonehearth:mount')
   if bed_data and mount and mount:get_user() == self._entity then
      self._ai:set_think_output({in_bed = true})
   else
      self._ai:set_think_output({in_bed = false})
   end
end

function BecomeIncapacitated:stop_thinking(ai, entity, args)
   self:destroy()
end

function BecomeIncapacitated:destroy()
   if self._became_incapacitated_listener then
      self._became_incapacitated_listener:destroy()
      self._became_incapacitated_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(BecomeIncapacitated)
   :execute('stonehearth_ace:become_incapacitated', {in_bed = ai.PREV.in_bed})
