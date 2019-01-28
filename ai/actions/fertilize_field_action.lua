local Entity = _radiant.om.Entity

local FertilizeField = radiant.class()
FertilizeField.name = 'fertilize field'
FertilizeField.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeField.does = 'stonehearth_ace:fertilize_field'
FertilizeField.args = {}
FertilizeField.priority = 0

function FertilizeField:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(entity))

   if self._inventory then
      self._tracker = self._inventory:get_item_tracker('stonehearth_ace:fertilizer_tracker')
      self._added_listener = radiant.events.listen(self._tracker, 'stonehearth:inventory_tracker:item_added', self, self._on_reconsider)
      self._job_changed_listener = radiant.events.listen(self._entity, 'stonehearth:job_changed', self, self._on_reconsider)
      self._job_level_changed_listener = radiant.events.listen(self._entity, 'stonehearth:level_up', self, self._on_reconsider)
      self:_on_reconsider()
   end
end

function FertilizeField:_on_reconsider()
   local job_component = self._entity:get_component('stonehearth:job')
   if job_component and job_component:curr_job_has_perk('farmer_fertilizer') then
      for id, fertilizer in self._tracker:get_tracking_data():each() do
         self._ai:set_think_output()
         return
      end
   end
end

function FertilizeField:stop_thinking(ai, entity)
   self:destroy()
end

function FertilizeField:destroy()
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
return ai:create_compound_action(FertilizeField)
         :execute('stonehearth:uri_to_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            uri = 'stonehearth_ace:farmer:field_layer:fertilizable'
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth.farming.rate_field,
            description = 'find fertilize layer',
         })
         :execute('stonehearth:key_to_entity_data_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            key = 'stonehearth_ace:fertilizer'
         })         
         :execute('stonehearth:pickup_item_type', {
            filter_fn = ai.PREV.filter_fn,
            description = 'find fertilizer'
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.BACK(5).item,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth:register_farm_field_worker', {
            field_layer = ai.BACK(6).item
         })
         :execute('stonehearth_ace:fertilize_crop_adjacent', {
            field_layer = ai.BACK(7).item,
            location = ai.BACK(2).location,
         })
         :execute('stonehearth:trigger_event', {
            source = stonehearth.personality,
            event_name = 'stonehearth:journal_event',
            event_args = {
               entity = ai.ENTITY,
               description = 'fertilize_entity',
            },
         })
