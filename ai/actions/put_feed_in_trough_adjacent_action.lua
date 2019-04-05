local Entity = _radiant.om.Entity

local FeedTroughAdjacent = radiant.class()
FeedTroughAdjacent.name = 'feed trough adjacent'
FeedTroughAdjacent.does = 'stonehearth_ace:feed_pasture_trough_adjacent'
FeedTroughAdjacent.args = {
   pasture = Entity,    -- the pasture the trough is in
   trough = Entity,     -- the trough to put feed in
   feed = Entity,
}
FeedTroughAdjacent.priority = 0

--[[
    Ace version:
    Changed the logic so it will retrieve animal feed based on material tags rather than specific uris.
    This allows us to add more fodder types.    
]]

function FeedTroughAdjacent:_is_correct_feed(feed, pasture)
   local shepherd_pasture = pasture:get_component('stonehearth:shepherd_pasture')
   if not shepherd_pasture then
      return false
   end
   local feed_material = shepherd_pasture:get_animal_feed_material()
   if feed and not radiant.entities.is_material(feed, feed_material) then
      local iconic_component = feed:get_component('stonehearth:iconic_form')
      if not iconic_component or (iconic_component and not radiant.entities.is_material(iconic_component:get_root_entity(), feed_material)) then
         return false
      end
   end

   return true
end

function FeedTroughAdjacent:run(ai, entity, args)
   local pasture = args.pasture
   local feed = args.feed
   if not self:_is_correct_feed(feed, pasture) then
      ai:abort('not carrying the correct type of feed')
      return
   end
   ai:execute('stonehearth:turn_to_face_entity', { entity = args.trough })
   ai:execute('stonehearth:run_effect', { effect = 'fiddle' })

   args.trough:get_component('stonehearth_ace:pasture_item'):set_trough_feed(feed)

   -- this is just used for granting the shepherd exp; might be slightly exploitable
   radiant.events.trigger_async(entity, 'stonehearth:feed_pasture', {pasture = pasture})

   ai:unprotect_argument(feed)
   radiant.entities.destroy_entity(feed)
end

return FeedTroughAdjacent
