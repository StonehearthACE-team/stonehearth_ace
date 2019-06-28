local Entity = _radiant.om.Entity
local GetDrinkTrivial = class()

GetDrinkTrivial.name = 'get drink trivial'
GetDrinkTrivial.does = 'stonehearth_ace:get_drink'
GetDrinkTrivial.args = {
   drink_filter_fn = 'function',
   drink_rating_fn = 'function',
}
GetDrinkTrivial.priority = {0, 1}

-- If you are already carrying drink, then you're good to go! This is only valid for humans

function GetDrinkTrivial:start_thinking(ai, entity, args)
   if ai.CURRENT.carrying ~= nil then
      local drink = radiant.entities.get_entity_data(ai.CURRENT.carrying, 'stonehearth_ace:drink')
      if drink and args.drink_filter_fn(ai.CURRENT.carrying)then
      	ai:set_utility(args.drink_rating_fn(ai.CURRENT.carrying, entity))
        ai:set_think_output()
      end
   end
end

return GetDrinkTrivial

