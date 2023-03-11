local AceGetFoodTrivial = radiant.class()

function AceGetFoodTrivial:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying ~= nil then
      local food = radiant.entities.get_entity_data(ai.CURRENT.carrying, 'stonehearth:food')
      -- we don't need to check if it passes the filter function, which now only validates food containers:
      -- the only possible way to carry non-container food is if it passed the filter function very recently
      if food then -- and args.food_filter_fn(ai.CURRENT.carrying) then
        ai:set_utility(args.food_rating_fn(ai.CURRENT.carrying, entity))
        ai:set_think_output()
      end
   end
end

return AceGetFoodTrivial
