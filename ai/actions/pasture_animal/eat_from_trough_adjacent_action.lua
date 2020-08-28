local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local Entity = _radiant.om.Entity
local log = radiant.log.create_logger('eat_trough_feed')

local EatTroughFeedAdjacent = radiant.class()
EatTroughFeedAdjacent.name = 'eat feed'
EatTroughFeedAdjacent.does = 'stonehearth_ace:eat_trough_feed_adjacent'
EatTroughFeedAdjacent.args = {
   trough = Entity,
}
EatTroughFeedAdjacent.priority = 0

function EatTroughFeedAdjacent:run(ai, entity, args)
   local trough = args.trough

   local feed_uri, quality = trough:get_component('stonehearth_ace:pasture_item'):eat_from_trough(entity)
   self._animal_feed_data = nil
   self._feed_quality = nil

   -- only if there was food to be eaten and it was successfully decremented from the trough will it return the feed uri
   if feed_uri then
      self._animal_feed_data =  radiant.entities.get_entity_data(feed_uri .. ':ground', 'stonehearth:animal_feed')
      self._feed_quality = quality
      ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.eat_from', { target = trough })

      ai:execute('stonehearth:run_effect', {
         effect = 'eat',
         times = self._animal_feed_data.effect_loops or 3
      })
   end
end

function EatTroughFeedAdjacent:stop(ai, entity, args)
   local expendable_resources_component = entity:add_component('stonehearth:expendable_resources')

   if self._animal_feed_data then
      local quality_chances = self._animal_feed_data.quality_chances
      if quality_chances then
         if self._feed_quality and self._feed_quality > 1 then
            quality_chances = item_quality_lib.modify_quality_table(quality_chances, self._feed_quality)
         end
         item_quality_lib.apply_quality(entity, quality_chances)
      end

      log:debug('%s successfully ate, gaining %s calories', entity, self._animal_feed_data.calorie_gain)

      -- if we're interrupted, go ahead and immediately finish eating
      -- we decided it was not fun to leave this hanging
      -- finally, adjust calories if necessary.  this might trigger callbacks which
      -- result in destroying the action, so make sure we do it LAST! (see calorie_obserer.lua)
      expendable_resources_component:modify_value('calories', self._animal_feed_data.calorie_gain)

      -- Animals that are fed get the Cared For buff.
      local equipment_component = entity:get_component('stonehearth:equipment')
      if equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag') then
         radiant.entities.add_buff(entity, 'stonehearth:buffs:shepherd:compassionate_shepherd')
      end
   end
end

return EatTroughFeedAdjacent
