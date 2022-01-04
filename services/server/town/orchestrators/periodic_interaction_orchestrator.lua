--[[
   Similar to craft_items_orchestrator. Observes periodic_interaction entities that register with the town,
   listening to when they're available for use, determining valid users, and creating tasks for them.
]]

local PeriodicInteractionOrchestrator

local log = radiant.log.create_logger('periodic_interaction'):set_prefix('orchestrator')

function PeriodicInteractionOrchestrator:run(town, args)

end

return PeriodicInteractionOrchestrator
