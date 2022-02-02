local Entity = _radiant.om.Entity

local FindBestReachableEntityByType = require 'stonehearth.ai.actions.find_best_reachable_entity_by_type'
local AceFindBestReachableEntityByType = class()
--AceFindBestReachableEntityByType.ACE_USE_MERGE_INTO_TABLE = true

local log = radiant.log.create_logger('find_best_reachable_entity_by_type')

FindBestReachableEntityByType.think_output = {
   item = Entity,                      -- the destination
   rating = 'number',                  -- the rating of the found item (1 if no rating_fn)
}

function AceFindBestReachableEntityByType:start(ai, entity, args)
   if not radiant.entities.exists(self._result) or not args.filter_fn(self._result) then
      if not stonehearth_ace.failed_filter_fn then
         stonehearth_ace.failed_filter_fn = {
            filter_fns = {},
            events = {}
         }
      end

      local filter_fns = stonehearth_ace.failed_filter_fn.filter_fns
      local filter_fn_events = stonehearth_ace.failed_filter_fn.events[args.filter_fn]
      if not filter_fn_events then
         table.insert(filter_fns, args.filter_fn)
         filter_fn_events = {
            filter_fn_index = #filter_fns,
            events = {}
         }
         stonehearth_ace.failed_filter_fn.events[args.filter_fn] = filter_fn_events
      end
      table.insert(filter_fn_events.events,
         {
            filter_fn = args.filter_fn,
            entity = entity,
            result = self._result
         }
      )
      log:debug('failed to match %s for %s in filter_fn %s: stonehearth_ace.failed_filter_fn.filter_fns[%s] => .events[%s]',
            self._result, entity, tostring(args.filter_fn), filter_fn_events.filter_fn_index, #filter_fn_events.events)
      
      ai:abort(string.format('destination %s is no longer valid at start. filter description: %s', tostring(self._result), tostring(self._description)))
   end

   if not radiant.entities.exists_in_world(self._result) then
      ai:abort(string.format('destination %s is no longer in world.', tostring(self._result)))
   end

   self._log:debug('start with %s at %s', self._result, radiant.entities.get_world_grid_location(self._result))
   self._started = true
end

function AceFindBestReachableEntityByType:_set_result(item, rating, args, entity)
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

return AceFindBestReachableEntityByType
