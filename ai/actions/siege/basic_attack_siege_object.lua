local Entity = _radiant.om.Entity
local log = radiant.log.create_logger('combat')

local AttackSiegeObject = radiant.class()

AttackSiegeObject.name = 'attack siege object'
AttackSiegeObject.does = 'stonehearth:combat:attack_siege_object'
AttackSiegeObject.args = {
   target = Entity,
}
AttackSiegeObject.priority = 0

function AttackSiegeObject:start_thinking(ai, entity, args)
   if not stonehearth.combat:is_killable_target_of_type(args.target, 'siege') then
      return
   end
   if stonehearth.combat:get_assaulting(entity) or stonehearth.combat:get_defending(entity) then
      return -- dont attack siege if we are attacking something or being attacked
   end

   if not self._aggro_table then
      self._aggro_table = entity:add_component('stonehearth:target_tables')
                                       :get_target_table('aggro')
   end

   -- XXX: Temporary solution, since siege entities currently do not attack and thus most of the time
   -- have a lower target table score than sentient enemies. So hearthlings that it can't reach (but
   -- are somewhat nearby) will be designated as the target instead of reachable siege (e.g. doors).
   -- TODO: Better method of calculation for aggro target table scores for siege objects.

   --if entity has reached the siege object destination, set that to the highest
   -- value in the target table so that it will attack the siege without jittering between
   -- targets it cannot reach.
   local best_entity, best_score = self._aggro_table:get_top()
   if best_entity ~= args.target and not stonehearth.combat:is_killable_target_of_type(best_entity, 'siege') then
      -- do we actually want to attack this target? if our top target is actually reachable, go with that instead
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

function AttackSiegeObject:stop(ai, entity, args)
   self._aggro_table = nil
end

local ai = stonehearth.ai
return ai:create_compound_action(AttackSiegeObject)
         :execute('stonehearth:combat:attack_after_cooldown', { target = ai.PREV.target })
