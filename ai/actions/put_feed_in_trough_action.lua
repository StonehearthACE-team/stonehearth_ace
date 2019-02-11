local Entity = _radiant.om.Entity

local FeedPastureTrough = radiant.class()
FeedPastureTrough.name = 'feed pasture animals'
FeedPastureTrough.status_text_key = 'stonehearth:ai.actions.status_text.feed_pasture_animals'
FeedPastureTrough.does = 'stonehearth_ace:feed_pasture_trough'
FeedPastureTrough.args = {
   pasture = Entity,        -- the pasture that needs to be fed
}
FeedPastureTrough.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(FeedPastureTrough)
         :execute('stonehearth_ace:wait_for_empty_pasture_trough', { pasture = ai.ARGS.pasture })
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:pickup_item_type', {
                  filter_fn = ai.BACK(2).filter_fn,
                  description = 'animal feed',
         })
         :execute('stonehearth:goto_entity', { entity = ai.BACK(3).trough })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(4).trough })
         :execute('stonehearth_ace:feed_pasture_trough_adjacent', { pasture = ai.ARGS.pasture, trough = ai.BACK(5).trough, feed = ai.BACK(3).item })
