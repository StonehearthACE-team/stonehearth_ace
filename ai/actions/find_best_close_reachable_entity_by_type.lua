local Entity = _radiant.om.Entity
local FindBestCloseReachableEntityByType = radiant.class()

FindBestCloseReachableEntityByType.name = 'find best reachable entity by type'
FindBestCloseReachableEntityByType.does = 'stonehearth_ace:find_best_close_reachable_entity_by_type'
FindBestCloseReachableEntityByType.args = {
   filter_fn = 'function',             -- filter describing the kinds of entities to consider.
   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
   description = 'string',             -- description of the initiating compound task (for debugging).
   ignore_leases = {                   -- whether to consider entities that are already leased.
      default = false,
      type = 'boolean'
   },
   max_items_to_examine = {            -- A limit on how many items to examine, for performance reasons.
      default = 200,
      type = 'number'
   },
   owner_player_id = {                         -- optional faction override to use when checking ai lease
      type = 'string',
      default = stonehearth.ai.NIL,
   },
   max_distance = {
      type = 'number',
      default = 30
   }
}
FindBestCloseReachableEntityByType.think_output = {
   item = Entity,                      -- the destination
   rating = 'number',                  -- the rating of the found item (1 if no rating_fn)
}
FindBestCloseReachableEntityByType.priority = {0, 1}  -- the rating of the found entity

local log = radiant.log.create_logger('find_best_reachable_entity_by_type')

function FindBestCloseReachableEntityByType:start_thinking(ai, entity, args)
   assert(args.filter_fn)

   -- Constant state
   self._ai = ai
   self._description = args.description
   self._log = log
   -- This is a hotspot, and creating loggers here is expensive, so only enable this for debugging.
   -- self._log = ai:get_log()

   -- Mutable state
   self._ready = false
   self._exhausted = false
   self._result = nil
   self._best_item = nil
   self._best_rating = 0
   self._location = ai.CURRENT.location
   self._items_examined = 0
   
   -- Too expensive: self._log:debug('start_thinking for %s; result=%s; if=%s', self._description, self._result or 'nil', self._if or 'nil')

   local exhausted = function()
      self._log:debug('exhausted item finder for %s @ %s', self._description, self._location)
      self._exhausted = true
      if self._best_item then
         self:_set_result(self._best_item, self._best_rating, args, entity)
      else
         ai:set_debug_progress('exhausted with no results')
      end
   end

   local consider = function(item)
      if ai.CURRENT.self_reserved[item:get_id()] then
         self._log:debug('already reserved')
         return false
      end

      self._items_examined = self._items_examined + 1
      if self._items_examined > args.max_items_to_examine then
         exhausted()
         return true  -- We reached the limit of how many items we are willing to examine.
      end
      
      local rating = args.rating_fn and math.min(1.0, args.rating_fn(item, entity)) or 1  -- If no rating function, accept first item.
      self._log:spam('considering %s => %f for %s', item, rating, self._description)
      if self._exhausted then
         -- We exhausted previously, so we will definitely be ready after this.
         -- Perhaps we just found something better (or had exhausted with no results).
         if not self._result or rating > self._best_rating then
            self._best_rating = rating
            self:_set_result(item, rating, args, entity)
            if rating == 1.0 then
               return true  -- We found the best thing ever!
            end
         end
         return false  -- We might still find something better.
      else
         -- Record this item if it's better than the best one we've found so far.
         if not self._best_item or rating > self._best_rating then
            self._best_item = item
            self._best_rating = rating
            if rating == 1.0 then
               self:_set_result(item, rating, args, entity)
               return true  -- We found the best thing ever!
            end
         end
         return false  -- Can't determine the best item until we've exhausted everything.
      end
   end
   
   -- Make sure any clear_think_outputs that might happen happen asynchronously.
   self._delay_start_timer = radiant.on_game_loop_once('FindBestCloseReachableEntityByType start_thinking', function()
         -- Too expensive: self._log:debug('creating item finder for %s @ %s', self._description, self._location)
         self._if = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
               self._location, args.filter_fn, consider, {
                  description = self._description,     -- for those of us in meat space
                  ignore_leases = args.ignore_leases,
                  exhausted_cb = exhausted,
                  reappraise_cb = consider,
                  owner_player_id = args.owner_player_id,
                  should_sort = false,                 -- we'll be sorting ourselves
                  max_distance = args.max_distance
               })
      end)
end

function FindBestCloseReachableEntityByType:stop_thinking(ai, entity, args)
   self._log:debug('stop_thinking for %s', self._description)
   if self._if then
      self._if:destroy()
      self._if = nil
      self._log:debug('destroying item finder for %s @ %s', self._description, self._location)
   end
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end
end

function FindBestCloseReachableEntityByType:start(ai, entity, args)
   if not radiant.entities.exists(self._result) or not args.filter_fn(self._result) then
      ai:abort(string.format('destination %s is no longer valid at start. filter description: %s', tostring(self._result), tostring(self._description)))
   end

   if not radiant.entities.exists_in_world(self._result) then
      ai:abort(string.format('destination %s is no longer in world.', tostring(self._result)))
   end

   self._log:debug('start with %s at %s', self._result, radiant.entities.get_world_grid_location(self._result))
   self._started = true
end

function FindBestCloseReachableEntityByType:stop(ai, entity, args)
   self._started = false
end

function FindBestCloseReachableEntityByType:_set_result(item, rating, args, entity)
   if self._started or not self._if then
      return  -- Too late now.
   end

   if self._ready then
      self._log:debug('found a better item; clearing previous choice for %s', item, self._description)
      self._ready = false
      self._ai:clear_think_output()
      
      if not self._if then
         return  -- Unreadying might cause other actions to start and kill us.
      end
   end

   self._log:debug('selecting %s (%s) for %s', item or 'NIL', rating or 'NIL', self._description)
   self._result = item
   self._ready = true
   self._ai:set_think_output({item = item, rating = rating})   -- Paul: changed to include rating
   if args.rating_fn then
      self._ai:set_utility(rating)
   end
   self._ai:set_debug_progress('selected: ' .. tostring(item) .. ' rating=' .. tostring(rating))
end

return FindBestCloseReachableEntityByType
