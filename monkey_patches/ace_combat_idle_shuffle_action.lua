local AceCombatIdleShuffle = radiant.class()

function AceCombatIdleShuffle:start_thinking(ai, entity, args)
   local no_shuffle = self:_no_shuffle(entity)
   if no_shuffle then
      return
   end

   self._entity = entity
   local target = args.target

   -- don't shuffle if we're in combat with someone at a lower elevation
   local location = radiant.entities.get_world_location(entity)
   local target_location = radiant.entities.get_world_location(target)
   if location.y > target_location + 3 then
      return
   end

   self._destination = self:_choose_destination(entity, target)
   if self._destination then
      ai:set_think_output()
   end
end

return AceCombatIdleShuffle
