local CompelledSleep = radiant.class()

CompelledSleep.name = 'compelled sleep'
CompelledSleep.does = 'stonehearth:compelled_behavior'
CompelledSleep.args = {}
CompelledSleep.priority = 1

local ai = stonehearth.ai

return ai:create_compound_action(CompelledSleep)
            :execute('stonehearth:wait_for_expendable_resource_above', {
                  resource_name = 'sleepiness',
                  value = stonehearth.constants.sleep.MAX_SLEEPINESS
               })
            :execute('stonehearth:set_posture', { posture = 'stonehearth:passed_out' })
            :execute('stonehearth:sleep_exhausted')
