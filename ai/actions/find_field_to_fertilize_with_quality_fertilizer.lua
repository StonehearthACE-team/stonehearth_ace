local Entity = _radiant.om.Entity

local FertilizeWithQualityFertilizer = radiant.class()
FertilizeWithQualityFertilizer.name = 'find field to fertilize'
FertilizeWithQualityFertilizer.status_text_key = 'stonehearth_ace:ai.actions.status_text.fertilize_field'
FertilizeWithQualityFertilizer.does = 'stonehearth_ace:find_field_to_fertilize'
FertilizeWithQualityFertilizer.args = {
   owner = {
      type = 'string',
      default = stonehearth.ai.NIL
   }
}
FertilizeWithQualityFertilizer.priority = 0.5

local _cached_fertilizer_qualities
local log = radiant.log.create_logger('fertilize_with_quality')

function FertilizeWithQualityFertilizer:start_thinking(ai, entity, args)
   if not _cached_fertilizer_qualities then
      -- get the min and max ilevels of fertilizers in the game and use that to bound the rating function
      local fertilizer = stonehearth.catalog:get_material_object('fertilizer')
      if fertilizer then
         local fertilizers = stonehearth.catalog:get_materials_to_matching_uris()[fertilizer:get_id()]
         local min, max
         for uri, _ in pairs(fertilizers) do
            local data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:fertilizer')
            if data and data.ilevel then
               min = math.min(min or data.ilevel, data.ilevel)
               max = math.max(max or data.ilevel, data.ilevel)
            end
         end

         if min and max then
            _cached_fertilizer_qualities = {
               min = min,
               max = max
            }
         end
      end

      if not _cached_fertilizer_qualities then
         _cached_fertilizer_qualities = {
            min = 0,
            max = 1
         }
      end
   
      _cached_fertilizer_qualities.range = math.max(1, _cached_fertilizer_qualities.max - _cached_fertilizer_qualities.min)
   end

   ai:set_think_output()
end

local get_farmer_field = function(fertilizable_layer)
   return fertilizable_layer:get_component('stonehearth:farmer_field_layer'):get_farmer_field()
end

local get_fertilizer_preference = function(fertilizable_layer)
   return get_farmer_field(fertilizable_layer):get_fertilizer_preference()
end

local create_farmer_field_filter_fn = function(owner)
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilize_field', 'quality', function(item)
      if owner and owner ~= item:get_player_id() then
         return false
      end
      
      if item:get_uri() ~= 'stonehearth_ace:farmer:field_layer:fertilizable' then
         return false
      end

      local fertilizer_preference = get_fertilizer_preference(item)

      return fertilizer_preference.quality and fertilizer_preference.quality ~= 0
   end)

   return filter_fn
end

local create_fertilizer_filter_fn = function(owner, fertilizable_layer)
   local fertilizer_preference = get_fertilizer_preference(fertilizable_layer)
   local key = tostring(fertilizer_preference.quality) .. '|' .. (owner or '')

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilizer', key, function(item)
         if owner and owner ~= item:get_player_id() then
            return false
         end
         
         local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
         if not data then
            return false
         end

         return data.ilevel ~= nil
      end)

   return filter_fn
end

local _high_quality_rating_fn = function(item)
   local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
   local rating = (data.ilevel - _cached_fertilizer_qualities.min) / _cached_fertilizer_qualities.range
   --log:debug('considering %s for high quality (%s)', item, rating)
   return rating
end

local _low_quality_rating_fn = function(item)
   local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
   local rating = (_cached_fertilizer_qualities.max - data.ilevel) / _cached_fertilizer_qualities.range
   --log:debug('considering %s for low quality (%s)', item, rating)
   return rating
end

local get_fertilizer_rating_fn = function(fertilizable_layer)
   local fertilizer_preference = get_fertilizer_preference(fertilizable_layer)

   if fertilizer_preference.quality > 0 then
      return _high_quality_rating_fn
   elseif fertilizer_preference.quality < 0 then
      return _low_quality_rating_fn
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(FertilizeWithQualityFertilizer)
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
            fertilizer_filter_fn = ai.CALL(create_fertilizer_filter_fn, ai.ARGS.owner, ai.BACK(2).item),
            fertilizer_rating_fn = ai.CALL(get_fertilizer_rating_fn, ai.BACK(2).item)
         })
