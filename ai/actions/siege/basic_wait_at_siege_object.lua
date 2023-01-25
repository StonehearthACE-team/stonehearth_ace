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

   if not self._aggro_table then
      self._aggro_table = entity:add_component('stonehearth:target_tables')
                                       :get_target_table('aggro')
   end

   local best_entity, best_score = self._aggro_table:get_top()
   if best_entity ~= args.target and not stonehearth.combat:is_killable_target_of_type(best_entity, 'siege') then
      if best_entity and _radiant.sim.topology.are_connected(entity, best_entity) then
         log:debug('%s can reach %s so shouldn\'t switch targets to siege entity %s', entity, best_entity, args.target)
         return
      end

      local new_score = best_score and (best_score + 1) or 1
      self._aggro_table:set_value(args.target, new_score)
      log:debug("%s setting siege target %s to aggro target value to %s", entity, tostring(args.target), tostring(new_score))
      ai:set_think_output({ target = args.target, score = new_score })
   end
end

function WaitAtSiegeObject:stop(ai, entity, args)
   self._aggro_table = nil
end

local ai = stonehearth.ai
return ai:create_compound_action(WaitAtSiegeObject)
         :execute('stonehearth:combat:idle', { target = ai.PREV.target })
