local Entity = _radiant.om.Entity
local log = radiant.log.create_logger('combat')

local WaitAtSiegeObject = radiant.class()

WaitAtSiegeObject.name = 'wait at siege object'
WaitAtSiegeObject.does = 'stonehearth:combat:attack_siege_object'
WaitAtSiegeObject.args = {
   target = Entity,
}
WaitAtSiegeObject.priority = 0

function WaitAtSiegeObject:start_thinking(ai, entity, args)
   ai:set_think_output({ target = args.target })
end

local ai = stonehearth.ai
return ai:create_compound_action(WaitAtSiegeObject)
         :execute('stonehearth:combat:idle', { target = ai.PREV.target })
