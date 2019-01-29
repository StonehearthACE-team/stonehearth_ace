local Entity = _radiant.om.Entity

local FertilizeAction = radiant.class()
FertilizeAction.name = 'fertilize'
FertilizeAction.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeAction.does = 'stonehearth_ace:fertilize'
FertilizeAction.args = {}
FertilizeAction.think_output = {
   owner = 'string'
}
FertilizeAction.priority = 0

function FertilizeAction:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   self._inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))

   if self._inventory then
      self._tracker = self._inventory:get_item_tracker('stonehearth_ace:fertilizer_tracker')
      self._added_listener = radiant.events.listen(self._tracker, 'stonehearth:inventory_tracker:item_added', self, self._on_reconsider)
      self._job_changed_listener = radiant.events.listen(self._entity, 'stonehearth:job_changed', self, self._on_reconsider)
      self._job_level_changed_listener = radiant.events.listen(self._entity, 'stonehearth:level_up', self, self._on_reconsider)
      self:_on_reconsider()
   end
end

function FertilizeAction:_on_reconsider()
   if not self._ready then
      local job_component = self._entity:get_component('stonehearth:job')
      if job_component and job_component:curr_job_has_perk('farmer_fertilizer') then
         for id, fertilizer in self._tracker:get_tracking_data():each() do
            self._ready = true
            self._ai:set_think_output({owner = self._entity:get_player_id() or ''})
            return
         end
      end
   end
end

function FertilizeAction:stop_thinking(ai, entity)
   self:destroy()
end

function FertilizeAction:destroy()
   if self._added_listener then
      self._added_listener:destroy()
      self._added_listener = nil
   end

   if self._job_changed_listener then
      self._job_changed_listener:destroy()
      self._job_changed_listener = nil
   end

   if self._job_level_changed_listener then
      self._job_level_changed_listener:destroy()
      self._job_level_changed_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(FertilizeAction)
         :execute('stonehearth_ace:find_field_to_fertilize', {
            owner = ai.PREV.owner
         })
