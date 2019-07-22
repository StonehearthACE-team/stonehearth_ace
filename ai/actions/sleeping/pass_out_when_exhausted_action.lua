local PassOutWhenExhausted = radiant.class()
PassOutWhenExhausted.name = 'pass out on max sleepiness'
PassOutWhenExhausted.does = 'stonehearth:sleep'
PassOutWhenExhausted.args = {}
PassOutWhenExhausted.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PassOutWhenExhausted)
            :execute('stonehearth:wait_for_expendable_resource_above', {
                  resource_name = 'sleepiness',
                  value = stonehearth.constants.sleep.MAX_SLEEPINESS
               })
            :execute('stonehearth:set_posture', { posture = 'stonehearth:passed_out' })
            :execute('stonehearth:pass_out_exhausted')
