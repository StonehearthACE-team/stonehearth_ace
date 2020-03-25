local Entity = _radiant.om.Entity

local HarvestField = radiant.class()
HarvestField.name = 'harvest field'
HarvestField.status_text_key = 'stonehearth:ai.actions.status_text.harvest_field'
HarvestField.does = 'stonehearth:harvest_field'
HarvestField.args = {}
HarvestField.priority = 0

local function create_filter_fn(owner, uri)
   return function(item)
         if owner ~= '' and item:get_player_id() ~= owner then
            -- not owned by the right person
            return false
         end
         return item:get_uri() == uri
      end
end

function HarvestField:start_thinking(ai, entity, args)
   local owner = entity:get_player_id()
   local filter_fn = function(item)
      if owner ~= '' and item:get_player_id() ~= owner then
         -- not owned by the right person
         return false
      end
      if item:get_uri() == 'stonehearth:farmer:field_layer:harvestable' then
         -- ACE: verify that the field has harvesting enabled!
         local farmer_field_layer = item:get_component('stonehearth:farmer_field_layer')
         local farmer_field = farmer_field_layer and farmer_field_layer:get_farmer_field()
         return farmer_field and farmer_field:is_harvest_enabled()
      end

      return false
   end

   ai:set_think_output({
      filter_fn = filter_fn
   })
end

local ai = stonehearth.ai
return ai:create_compound_action(HarvestField)
         :execute('stonehearth:wait_for_town_inventory_space')
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(2).filter_fn,
            rating_fn = stonehearth.farming.rate_field,
            description = 'find harvest layer',
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(3).filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(2).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.BACK(1).path,
            stop_distance = ai.CALL(radiant.entities.get_harvest_range, ai.ENTITY),
         })
         :execute('stonehearth:reserve_entity_destination', {
            entity = ai.BACK(4).item,
            location = ai.BACK(2).path:get_destination_point_of_interest()
         })
         :execute('stonehearth:register_farm_field_worker', {
            field_layer = ai.BACK(5).item
         })
         :execute('stonehearth:harvest_crop_adjacent', {
            field_layer = ai.BACK(6).item,
            location = ai.BACK(2).location,
         })
         :execute('stonehearth:trigger_event', {
            source = stonehearth.personality,
            event_name = 'stonehearth:journal_event',
            event_args = {
               entity = ai.ENTITY,
               description = 'harvest_entity',
            },
         })
         :execute('stonehearth:drop_carrying_if_stacks_full', {})
