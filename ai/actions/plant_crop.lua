local PlantCrop = radiant.class()
PlantCrop.name = 'plant crop entire field'
PlantCrop.does = 'stonehearth:plant_crop'
PlantCrop.status_text_key = 'stonehearth:ai.actions.status_text.plant_crop'
PlantCrop.args = {}
PlantCrop.priority = 0

function PlantCrop:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying == nil then
      local owner = entity:get_player_id()
      local filter_fn = function(item)
         if owner ~= '' and item:get_player_id() ~= owner then
            -- not owned by the right person
            return false
         end
         if item:get_uri() == 'stonehearth:farmer:field_layer:plantable' then
            -- ACE: verify that the field has harvesting enabled!
            local farmer_field_layer = item:get_component('stonehearth:farmer_field_layer')
            local farmer_field = farmer_field_layer and farmer_field_layer:get_farmer_field()
            return farmer_field and farmer_field:is_planting_enabled()
         end

         return false
      end
      ai:set_think_output({
         filter_fn = filter_fn
      })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PlantCrop)
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth.farming.rate_field,
            description = 'find plant layer',
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(2).filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.BACK(3).item,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth:register_farm_field_worker', {
            field_layer = ai.BACK(4).item
         })
         :execute('stonehearth:plant_field_adjacent', {
            field_layer = ai.BACK(5).item,
            location = ai.BACK(2).location,
         })
