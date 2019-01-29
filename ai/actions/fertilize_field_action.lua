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
FertilizeField.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(FertilizeField)
         :execute('stonehearth:pickup_item_type', {
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
