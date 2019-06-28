local DrinkOnChair = class()
DrinkOnChair.name = 'drink on a chair'
DrinkOnChair.does = 'stonehearth_ace:find_seat_and_drink'
DrinkOnChair.args = {}
DrinkOnChair.priority = 1

local ai = stonehearth.ai
return ai:create_compound_action(DrinkOnChair)
            :execute('stonehearth:sit_on_chair')
            :execute('stonehearth_ace:drink_carrying')
