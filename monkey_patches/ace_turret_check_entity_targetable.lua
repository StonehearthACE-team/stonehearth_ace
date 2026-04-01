local AceSiegeCheckEntityTargetable = radiant.class()

function AceSiegeCheckEntityTargetable:_update_think_output(ai, entity, args)
   local clear_think_output = function()
         if self._ready then
            ai:clear_think_output()
            self._ready = false
         end
      end

   local siege_weapon_component = entity:get_component('stonehearth:siege_weapon')
   -- Check entity is a siege weapon and has some remaining uses left
   if not siege_weapon_component or not siege_weapon_component:has_remaining_uses() then
      clear_think_output()
      return
   end
   
   local target_exclusion_buffs = siege_weapon_component:get_target_exclusion_buffs()
   if target_exclusion_buffs then
      for buff, listed in pairs(target_exclusion_buffs) do
         if listed and radiant.entities.has_buff(args.target, buff) then
            clear_think_output()
            return
         end
      end
   end

   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      clear_think_output()
      return
   end

   -- Don't target/attack if we (not the target) are outside the leash
   if stonehearth.combat:is_entity_outside_leash(entity) then
      clear_think_output()
      return
   end

   if not stonehearth.combat:in_range_and_has_line_of_sight(entity, args.target, weapon) then
      clear_think_output()
      return
   end

   if radiant.entities.is_standing_on_ladder(entity) then
      -- We generally want to prohibit combat on ladders. This case is particularly unfair,
      -- because the ranged unit can attack, but melee units can't find an adjacent to retaliate.
      clear_think_output()
      return
   end

   if not self._ready then
      self._ready = true
      ai:set_think_output()
   end
end

return AceSiegeCheckEntityTargetable
