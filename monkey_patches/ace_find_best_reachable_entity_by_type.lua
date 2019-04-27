local Entity = _radiant.om.Entity

local FindBestReachableEntityByType = require 'stonehearth.ai.actions.find_best_reachable_entity_by_type'
local AceFindBestReachableEntityByType = class()

AceFindBestReachableEntityByType.think_output = {
   item = Entity,                      -- the destination
   rating = 'number',                  -- the rating of the found item (1 if no rating_fn)
}

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
