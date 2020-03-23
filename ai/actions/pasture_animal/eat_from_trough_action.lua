local rng = _radiant.math.get_default_rng()
local EatTroughFeed = radiant.class()

EatTroughFeed.name = 'eat feed from trough'
EatTroughFeed.does = 'stonehearth:eat'
EatTroughFeed.args = {
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
EatTroughFeed.priority = {0, 1}

function EatTroughFeed:start_thinking(ai, entity, args)
   self._pasture = nil
   self._ai = ai
   self._entity = entity
   self._ready = false

   local pasture_tag = entity:get_component('stonehearth:equipment'):has_item_type('stonehearth:pasture_equipment:tag')
   if pasture_tag then
      local pasture = pasture_tag:get_component('stonehearth:shepherded_animal'):get_pasture()
      if pasture and pasture:is_valid() then
         self._pasture = pasture
         self._on_feed_changed_listener = radiant.events.listen(pasture, 'stonehearth_ace:shepherd_pasture:trough_feed_changed', self, self._rethink)
         self._calorie_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:calories', self, self._rethink)
         self._timer = stonehearth.calendar:set_interval("eat_action hourly", '10m+5m', function() self:_rethink() end, '20m')
         self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
      end
   end
end

function EatTroughFeed:_rethink(trough)
   local consumption = self._entity:get_component('stonehearth:consumption')
   if not consumption then
      -- probably still an egg or something?
      return
   end

   local hunger_score = consumption:get_hunger_score()
   local min_hunger_to_eat = consumption:get_min_hunger_to_eat_now()
   local pasture = self._pasture

   if not pasture or not pasture:is_valid() then
      self._log:warning('pasture destroyed')
      return
   end

   local pasture_comp = pasture:get_component('stonehearth:shepherd_pasture')
   -- prioritize newly restocked troughs
   local troughs = trough and trough.trough and {trough.trough} or pasture_comp:get_fed_troughs()

   self._ai:set_debug_progress(string.format('hunger = %s; min to eat now = %s', hunger_score, min_hunger_to_eat))
   if troughs and hunger_score >= min_hunger_to_eat then
      self:_mark_ready(troughs)
   else
      self:_mark_unready()
   end

   self._ai:set_utility(hunger_score)
end

function EatTroughFeed:_mark_ready(troughs)
   if not self._ready then
      self._ready = true

      local trough = troughs[rng:get_int(1, #troughs)]
      self._ai:set_think_output({
         trough = trough
      })
   end
end

function EatTroughFeed:_mark_unready()
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_food')
   end
end

function EatTroughFeed:stop_thinking(ai, entity)
   if self._on_feed_changed_listener then
      self._on_feed_changed_listener:destroy()
      self._on_feed_changed_listener = nil
   end

   if self._calorie_listener then
      self._calorie_listener:destroy()
      self._calorie_listener = nil
   end

   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(EatTroughFeed)
   :execute('stonehearth:goto_entity', {entity = ai.PREV.trough})
   :execute('stonehearth:turn_to_face_entity', { entity = ai.BACK(2).trough })
   :execute('stonehearth_ace:eat_trough_feed_adjacent', { trough = ai.BACK(3).trough })
