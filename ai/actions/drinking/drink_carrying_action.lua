local DrinkCarrying = class()
DrinkCarrying.name = 'drink carrying'
DrinkCarrying.does = 'stonehearth_ace:drink_carrying'
DrinkCarrying.args = { }
DrinkCarrying.priority = 0

function DrinkCarrying:run(ai, entity)
   local drink = radiant.entities.get_carrying(entity)
   if not drink then
      ai:abort('cannot drink. not carrying anything!')
   end

   ai:execute('stonehearth_ace:consume_drink', {
      drink = drink,
   })
end

function DrinkCarrying:stop(ai, entity, args)
end

return DrinkCarrying
