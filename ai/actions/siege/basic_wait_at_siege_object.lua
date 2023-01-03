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
   if not stonehearth.combat:is_killable_target_of_type(args.target, 'siege') then
      return
   end
   if stonehearth.combat:get_assaulting(entity) or stonehearth.combat:get_defending(entity) then
      return -- dont wait at siege object if we are attacking something or being attacked
   end

   ai:set_think_output({ target = args.target })
end

local ai = stonehearth.ai
return ai:create_compound_action(WaitAtSiegeObject)
         :execute('stonehearth:combat:idle', { target = ai.PREV.target })
