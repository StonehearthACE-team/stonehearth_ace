local Entity = _radiant.om.Entity
local GetDrinkTrivial = class()

GetDrinkTrivial.name = 'get drink trivial'
GetDrinkTrivial.does = 'stonehearth_ace:get_drink'
GetDrinkTrivial.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = {           -- a rating function that returns a score 0-1 given the item and entity
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
GetDrinkTrivial.priority = {0, 1}

-- If you are already carrying drink, then you're good to go! This is only valid for humans

function GetDrinkTrivial:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying ~= nil then
      local drink = radiant.entities.get_entity_data(ai.CURRENT.carrying, 'stonehearth_ace:drink')
      -- we don't need to check if it passes the filter function, which now only validates drink containers:
      -- the only possible way to carry a non-container drink is if it passed the filter function very recently
      if drink then -- and args.drink_filter_fn(ai.CURRENT.carrying)then
         ai:set_utility(args.drink_rating_fn and args.drink_rating_fn(ai.CURRENT.carrying, entity) or 1)
         ai:set_think_output()
      end
   end
end

return GetDrinkTrivial

