local Entity = _radiant.om.Entity

local FertilizeField = radiant.class()
FertilizeField.name = 'fertilize field'
FertilizeField.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeField.does = 'stonehearth_ace:fertilize_field'
FertilizeField.args = {
   field = Entity,                     -- the field we're going to fertilize
   fertilizer_filter_fn = 'function',  -- filter function for the fertilizer, based on the field
   fertilizer_rating_fn = {            -- rating function for the fertilizer, based on the field
      type = 'function',
      default = stonehearth.ai.NIL
   }
}
FertilizeField.priority = {0, 1}

function FertilizeField:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._field = args.field
   self._ready = false
   self._job_changed_listener = radiant.events.listen(self._entity, 'stonehearth:job_changed', self, self._on_reconsider)
   self._job_level_changed_listener = radiant.events.listen(self._entity, 'stonehearth:level_up', self, self._on_reconsider)
   self:_on_reconsider()
end

function FertilizeField:_on_reconsider()
   if not self._ready then
      local job_component = self._entity:get_component('stonehearth:job')
      if job_component and job_component:curr_job_has_perk('farmer_fertilizer') then
         self._ready = true
         self._ai:set_utility(stonehearth.farming.rate_field(self._field, self._entity))
         self._ai:set_think_output({})
      end
   end
end

function FertilizeField:stop_thinking(ai, entity)
   self:destroy()
end

function FertilizeField:destroy()
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
         :execute('stonehearth_ace:drop_and_pickup_item_type', {
            filter_fn = ai.ARGS.fertilizer_filter_fn,
            rating_fn = ai.ARGS.fertilizer_rating_fn,
            description = 'find fertilizer'
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.ARGS.field
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.ARGS.field,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth:register_farm_field_worker', {
            field_layer = ai.ARGS.field
         })
         :execute('stonehearth_ace:fertilize_crop_adjacent', {
            field_layer = ai.ARGS.field,
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
