local PassOut = radiant.class()

PassOut.name = 'pass out'
PassOut.status_text_key = 'stonehearth:ai.actions.status_text.sleep_on_ground'
PassOut.does = 'stonehearth:pass_out_exhausted'
PassOut.args = {}
PassOut.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PassOut)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:run_effect', { effect = 'goto_passed_out' })
         :execute('stonehearth:set_posture', { posture = 'stonehearth:passed_out' })
         :execute('stonehearth:sleep_on_ground_adjacent')
