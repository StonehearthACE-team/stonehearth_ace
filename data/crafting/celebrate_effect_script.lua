local rng = _radiant.math.get_default_rng()
local celebrate_effect = {}

function celebrate_effect.post_craft(ai, crafter, workshop, recipe, all_products)
   if ai then
      local celebration_effects = { 'emote_dance_themonkey', 'emote_applaud', 'emote_proud', 'emote_dance_handsup', 'emote_applaud_upward', 'emote_fistpump' }
      ai:execute('stonehearth:run_effect', { effect = celebration_effects[rng:get_int(1, #celebration_effects)] })
   end
end

return celebrate_effect