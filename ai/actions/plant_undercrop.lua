local PlantUndercrop = radiant.class()
PlantUndercrop.name = 'plant undercrop entire underfield'
PlantUndercrop.does = 'stonehearth_ace:plant_undercrop'
PlantUndercrop.status_text_key = 'stonehearth_ace:ai.actions.status_text.plant_undercrop'
PlantUndercrop.args = {}
PlantUndercrop.priority = 0

function PlantUndercrop:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying == nil then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PlantUndercrop)
         :execute('stonehearth:uri_to_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            uri = 'stonehearth_ace:mountain_folk:grower:underfield_layer:plantable'
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth_ace.underfarming.rate_underfield,
            description = 'find plant layer',
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.PREV.item
         })
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.BACK(3).item,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth_ace:register_underfarm_underfield_worker', {
            underfield_layer = ai.BACK(4).item
         })
         :execute('stonehearth_ace:plant_underfield_adjacent', {
            underfield_layer = ai.BACK(5).item,
            location = ai.BACK(2).location,
         })
