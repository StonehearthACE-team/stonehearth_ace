local Entity = _radiant.om.Entity

local FeedPastureTrough = radiant.class()
FeedPastureTrough.name = 'feed pasture trough'
FeedPastureTrough.status_text_key = 'stonehearth:ai.actions.status_text.feed_pasture_animals'
FeedPastureTrough.does = 'stonehearth_ace:feed_pasture_trough'
FeedPastureTrough.args = {
   pasture = Entity,             -- the pasture that needs to be fed
   trough = Entity,              -- the specific trough in the pasture to be filled
   feed_filter_fn = 'function'   -- filter_fn for feed to fill the trough
}
FeedPastureTrough.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(FeedPastureTrough)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:pickup_item_type', {
                  filter_fn = ai.ARGS.feed_filter_fn,
                  description = 'animal feed',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.trough })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.trough })
         :execute('stonehearth_ace:feed_pasture_trough_adjacent', {
            pasture = ai.ARGS.pasture,
            trough = ai.ARGS.trough,
            feed = ai.BACK(3).item
         })
