local GrazeOnGround = radiant.class()

GrazeOnGround.name = 'graze on grass'
GrazeOnGround.does = 'stonehearth:eat'
GrazeOnGround.args = {
   grass_uri = {
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
GrazeOnGround.priority = 0

function GrazeOnGround:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'calories') == nil then
      ai:set_debug_progress('dead: have no calories resource')
      return
   end

   -- Constant state
   self._ai = ai
   self._entity = entity
   self._grass_uri = args.grass_uri or 'stonehearth_ace:terrain:pasture_grass'

   -- Mutable state
   self._ready = false
   self._food_filter_fn = stonehearth.ai:filter_from_key('food_filter', 'grazing grass', function(item)
         return item:get_uri() == self._grass_uri
      end)
   self._food_rating_fn = function(item) return 1 end
   
   self._calorie_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:calories', self, self._rethink)
   self._timer = stonehearth.calendar:set_interval("eat_action hourly", '10m+5m', function() self:_rethink() end, '20m')
   self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function GrazeOnGround:stop_thinking(ai, entity, args)
   if self._calorie_listener then
      self._calorie_listener:destroy()
      self._calorie_listener = nil
   end
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

function GrazeOnGround:_rethink()
   -- if there's feed out, don't do any grazing
   local pasture_tag = self._entity:get_component('stonehearth:equipment'):has_item_type('stonehearth:pasture_equipment:tag')
   if pasture_tag then
      local pasture = pasture_tag:get_component('stonehearth:shepherded_animal'):get_pasture()
      if pasture and pasture:is_valid() then
         local feed_entity = pasture:get_component('stonehearth:shepherd_pasture'):get_feed()
         if feed_entity then
            self:_mark_unready()
            return
         end
      end
   end

   local consumption = self._entity:get_component('stonehearth:consumption')
   local hunger_score = consumption:get_hunger_score()
   local min_hunger_to_eat = consumption:get_min_hunger_to_eat_now()
   
   self._ai:set_debug_progress(string.format('hunger = %s; min to eat now = %s', hunger_score, min_hunger_to_eat))
   if hunger_score >= min_hunger_to_eat then
      self:_mark_ready()
   else
      self:_mark_unready()
   end
end

function GrazeOnGround:_mark_ready()
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({
         food_filter_fn = self._food_filter_fn,
         food_rating_fn = self._food_rating_fn,
      })
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:looking_for_food')
   end
end

function GrazeOnGround:_mark_unready()
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(GrazeOnGround)
   :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.PREV.food_filter_fn,
            rating_fn = ai.PREV.food_rating_fn,
            description = 'find grass to graze',
         })
   :execute('stonehearth:goto_entity', {entity = ai.PREV.item})
   :execute('stonehearth:turn_to_face_entity', {entity = ai.BACK(2).item})
   :execute('stonehearth:eat_feed_adjacent', { food = ai.BACK(3).item })
