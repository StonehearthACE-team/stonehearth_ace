local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local Entity = _radiant.om.Entity

local FeedPastureAdjacent = radiant.class()
FeedPastureAdjacent.name = 'feed pasture adjacent'
FeedPastureAdjacent.does = 'stonehearth:feed_pasture_adjacent'
FeedPastureAdjacent.args = {
   pasture = Entity,      -- the pasture to feed
   feed = Entity,
}
FeedPastureAdjacent.priority = 0

--[[
    Ace version:
    Changed the logic so it will retrieve animal feed based on material tags rather than specific uris.
    This allows us to add more fodder types.    
]]

function FeedPastureAdjacent:_is_correct_feed(entity, pasture)
   local shepherd_pasture = pasture:get_component('stonehearth:shepherd_pasture')
   if not shepherd_pasture then
      return false
   end
   local feed_material = shepherd_pasture:get_animal_feed_material()
   if entity and not radiant.entities.is_material(entity, feed_material) then
      local iconic_component = entity:get_component('stonehearth:iconic_form')
      if not iconic_component or (iconic_component and not radiant.entities.is_material(iconic_component:get_root_entity(), feed_material)) then
         return false
      end
   end

   if shepherd_pasture:get_feed() ~= nil then
      -- do not feed a pasture that already has feed
      return false
   end
   return true
end

function FeedPastureAdjacent:run(ai, entity, args)
   local pasture = args.pasture
   local feed = args.feed
   if not self:_is_correct_feed(feed, pasture) then
      ai:abort('not carrying the correct type of feed')
      return
   end
   ai:execute('stonehearth:run_effect', { effect = 'fiddle' })

   local pasture_component = pasture:get_component('stonehearth:shepherd_pasture')
   local feed_uri = feed:get_uri()
   local feed_location = radiant.entities.get_world_grid_location(feed)

   local feed_on_ground = radiant.entities.create_entity(feed_uri..":ground", { owner = entity })
   item_quality_lib.copy_quality(feed, feed_on_ground)
   radiant.terrain.place_entity_at_exact_location(feed_on_ground, feed_location)
   pasture_component:set_feed(feed_on_ground)

   radiant.events.trigger_async(entity, 'stonehearth:feed_pasture', {pasture = pasture})

   ai:unprotect_argument(feed)
   radiant.entities.destroy_entity(feed)
end

return FeedPastureAdjacent
