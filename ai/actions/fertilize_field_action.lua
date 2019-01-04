local Entity = _radiant.om.Entity

local FertilizeField = radiant.class()
FertilizeField.name = 'fertilize field'
FertilizeField.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeField.does = 'stonehearth_ace:fertilize_field'
FertilizeField.args = {}
FertilizeField.priority = 0

function FertilizeField:start_thinking(ai, entity, args)
   local job_component = entity:get_component('stonehearth:job')
   if not job_component or not job_component:curr_job_has_perk('farmer_fertilizer') then
      ai:clear_think_output()
      return
   end

   ai:set_think_output()
end

local ai = stonehearth.ai
return ai:create_compound_action(FertilizeField)
         :execute('stonehearth:key_to_entity_data_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            key = 'stonehearth_ace:fertilizer'
         })         
         :execute('stonehearth:pickup_item_type', {
            filter_fn = ai.PREV.filter_fn,
            description = 'find fertilizer'
         })
         :execute('stonehearth:uri_to_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            uri = 'stonehearth_ace:farmer:field_layer:fertilizable'
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth.farming.rate_field,
            description = 'find fertilize layer',
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.BACK(3).item,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth:register_farm_field_worker', {
            field_layer = ai.BACK(4).item
         })
         :execute('stonehearth_ace:fertilize_crop_adjacent', {
            field_layer = ai.BACK(5).item,
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
