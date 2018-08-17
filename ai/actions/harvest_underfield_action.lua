local Entity = _radiant.om.Entity

local HarvestUnderfield = radiant.class()
HarvestUnderfield.name = 'harvest underfield'
HarvestUnderfield.status_text_key = 'stonehearth_ace:ai.actions.status_text.harvest_underfield'
HarvestUnderfield.does = 'stonehearth_ace:harvest_underfield'
HarvestUnderfield.args = {}
HarvestUnderfield.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(HarvestUnderfield)
         :execute('stonehearth:wait_for_town_inventory_space')
         :execute('stonehearth:uri_to_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            uri = 'stonehearth_ace:mountain_folk:grower:underfield_layer:harvestable'
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth_ace.underfarming.rate_underfield,
            description = 'find underharvest layer',
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
         :execute('stonehearth_ace:register_underfarm_underfield_worker', {
            underfield_layer = ai.BACK(4).item
         })
         :execute('stonehearth_ace:harvest_undercrop_adjacent', {
            underfield_layer = ai.BACK(5).item,
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
