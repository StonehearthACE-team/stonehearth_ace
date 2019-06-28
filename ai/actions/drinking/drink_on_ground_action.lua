local DrinkOnGround = class()
DrinkOnGround.name = 'drink on the ground'
DrinkOnGround.does = 'stonehearth_ace:find_seat_and_drink'
DrinkOnGround.args = {}
DrinkOnGround.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(DrinkOnGround)
            :execute('stonehearth:wander', { radius = 5, radius_min = 3 })
            :execute('stonehearth:sit_on_ground')
            :execute('stonehearth_ace:drink_carrying')
