local TillEntireUnderfield = radiant.class()
TillEntireUnderfield.name = 'till entire underfield'
TillEntireUnderfield.status_text_key = 'stonehearth_ace:ai.actions.status_text.plant_undercrop'
TillEntireUnderfield.does = 'stonehearth_ace:till_entire_underfield'
TillEntireUnderfield.args = {}
TillEntireUnderfield.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(TillEntireUnderfield)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:uri_to_filter_fn', {
            owner = ai.ENTITY:get_player_id(),
            uri = 'stonehearth_ace:mountain_folk:grower:underfield_layer:tillable'
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.filter_fn,
            rating_fn = stonehearth_ace.underfarming.rate_underfield,
            description = 'find till layer',
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
         :execute('stonehearth_ace:till_underfield_adjacent', {
            underfield_layer = ai.BACK(5).item,
            location = ai.BACK(2).location,
         })
