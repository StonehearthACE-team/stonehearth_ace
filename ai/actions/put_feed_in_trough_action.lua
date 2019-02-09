-- NOT YET IMPLEMENTED; just a copy of original action

local Entity = _radiant.om.Entity

local FeedPastureAnimals = radiant.class()
FeedPastureAnimals.name = 'feed pasture animals'
FeedPastureAnimals.status_text_key = 'stonehearth:ai.actions.status_text.feed_pasture_animals'
FeedPastureAnimals.does = 'stonehearth:feed_pasture_animals'
FeedPastureAnimals.args = {
   pasture = Entity,        -- the pasture that needs to be fed
}
FeedPastureAnimals.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(FeedPastureAnimals)
         :execute('stonehearth:wait_for_unfed_pasture', { pasture = ai.ARGS.pasture })
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:pickup_item_type', {
                  filter_fn = ai.BACK(2).filter_fn,
                  description = 'animal feed',
         })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.pasture })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.pasture })
         :execute('stonehearth:find_direct_path_to_location', {
            destination = ai.ARGS.pasture:get_component('stonehearth:shepherd_pasture'):get_center_point():to_int(),
            allow_incomplete_path = true,
            reversible_path = true,
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:feed_pasture_adjacent', { pasture = ai.ARGS.pasture, feed = ai.BACK(6).item })
