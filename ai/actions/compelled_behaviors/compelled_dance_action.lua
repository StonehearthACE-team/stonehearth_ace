local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()

local CompelledDance = radiant.class()

CompelledDance.name = 'compelled_dance'
CompelledDance.args = {}
CompelledDance.does = 'stonehearth:compelled_behavior'
CompelledDance.priority = 1
CompelledDance.weight = 2

local EFFECTS = {
   'emote_dance_handsup_no_effect',
   'emote_dance_shuffle_no_effect',
   'emote_dance_themonkey_no_effect',
   'emote_laugh'
}

function CompelledDance:start_thinking(ai, entity, args)
   ai:set_think_output({
         effect = EFFECTS[rng:get_int(1, #EFFECTS)],
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(CompelledDance)  -- Walk leisurely.
            :execute('stonehearth:run_effect', { effect = ai.BACK(1).effect })
            :execute('stonehearth:wander', { radius = 3 })
