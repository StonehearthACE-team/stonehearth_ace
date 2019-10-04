local validator = radiant.validator
local CombatCallHandler = class()

function CombatCallHandler:cancel_combat_order_on_target(session, response, target)
   validator.expect_argument_types({'Entity'}, target)

   stonehearth.combat_server_commands:cancel_order_on_target(session.player_id, target)
end

return CombatCallHandler
