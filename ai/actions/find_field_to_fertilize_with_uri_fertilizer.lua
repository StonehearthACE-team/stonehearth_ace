local Entity = _radiant.om.Entity

local log = radiant.log.create_logger('find_field_to_fertilize')

local FertilizeWithSpecificFertilizer = radiant.class()
FertilizeWithSpecificFertilizer.name = 'find field to fertilize'
FertilizeWithSpecificFertilizer.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeWithSpecificFertilizer.does = 'stonehearth_ace:find_field_to_fertilize'
FertilizeWithSpecificFertilizer.args = {
   owner = {
      type = 'string',
      default = stonehearth.ai.NIL
   }
}
FertilizeWithSpecificFertilizer.priority = 1

local get_farmer_field = function(fertilizable_layer)
   return fertilizable_layer:get_component('stonehearth:farmer_field_layer'):get_farmer_field()
end

local get_fertilizer_preference = function(fertilizable_layer)
   return get_farmer_field(fertilizable_layer):get_fertilizer_preference()
end

local create_farmer_field_filter_fn = function(owner)
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilize_field', 'uri', function(item)
      if owner and owner ~= item:get_player_id() then
         return false
      end
      
      if item:get_uri() ~= 'stonehearth_ace:farmer:field_layer:fertilizable' then
         return false
      end

      local fertilizer_preference = get_fertilizer_preference(item)

      return fertilizer_preference.uri ~= nil
   end)

   return filter_fn
end

local create_fertilizer_filter_fn = function(owner, fertilizable_layer)
   local fertilizer_preference = get_fertilizer_preference(fertilizable_layer)
   local key = fertilizer_preference.uri .. '|' .. (owner or '')

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilizer', key, function(item)
         if owner and owner ~= item:get_player_id() then
            return false
         end
         
         local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
         if not data then
            return false
         end

         log:debug('checking if fertilizer %s matches preference %s (%s)', item, fertilizer_preference.uri, item:get_uri() == fertilizer_preference.uri)

         return fertilizer_preference.uri == item:get_uri()
      end)

   return filter_fn
end

local ai = stonehearth.ai
return ai:create_compound_action(FertilizeWithSpecificFertilizer)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.CALL(create_farmer_field_filter_fn, ai.ARGS.owner),
            rating_fn = stonehearth.farming.rate_field,
            description = 'find fertilize layer',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.CALL(get_farmer_field, ai.BACK(1).item),
            event_name = 'stonehearth_ace:farmer_field:fertilizer_preference_changed',
         })
         :execute('stonehearth_ace:fertilize_field', {
            field = ai.BACK(2).item,
            fertilizer_filter_fn = ai.CALL(create_fertilizer_filter_fn, ai.ARGS.owner, ai.BACK(2).item)
         })
