-- NOT YET IMPLEMENTED; just a copy of original action

local EatFeedOnGround = radiant.class()

EatFeedOnGround.name = 'eat feed from ground'
EatFeedOnGround.does = 'stonehearth:eat'
EatFeedOnGround.args = {
   food_quality = {
      type = 'number',
      default = stonehearth.ai.NIL,
   },
   food_preferences = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   food_priority = {
      type = 'number',
      default = stonehearth.ai.NIL,
   }
}
EatFeedOnGround.priority = 0

function EatFeedOnGround:start_thinking(ai, entity, args)
   self._pasture = nil
   self._ai = ai
   self._ready = false

   local pasture_tag = entity:get_component('stonehearth:equipment'):has_item_type('stonehearth:pasture_equipment:tag')
   if pasture_tag then
      local pasture = pasture_tag:get_component('stonehearth:shepherded_animal'):get_pasture()
      if pasture and pasture:is_valid() then
         self._on_feed_changed_listener = radiant.events.listen(pasture, 'stonehearth:shepherd_pasture:feed_changed', self, self._on_feed_changed)
         self:_on_feed_changed(pasture)  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
      end
   end
end

function EatFeedOnGround:_on_feed_changed(pasture)
   if not pasture or not pasture:is_valid() then
      self._log:warning('pasture destroyed')
      return
   end

   local feed_entity = pasture:get_component('stonehearth:shepherd_pasture'):get_feed()

   if feed_entity and not self._ready then
      self._ready = true

      self._ai:set_think_output({
         feed = feed_entity
      })
   elseif not feed_entity and self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

function EatFeedOnGround:stop_thinking(ai, entity)
   if self._on_feed_changed_listener then
      self._on_feed_changed_listener:destroy()
      self._on_feed_changed_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(EatFeedOnGround)
   :execute('stonehearth:goto_entity', {entity = ai.PREV.feed})
   :execute('stonehearth:eat_feed_adjacent', { food = ai.BACK(2).feed })
