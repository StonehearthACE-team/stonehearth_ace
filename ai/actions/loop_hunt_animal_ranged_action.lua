local Entity = _radiant.om.Entity

local LoopHuntAnimalRanged = radiant.class()

LoopHuntAnimalRanged.name = 'keep hunting this animal'
LoopHuntAnimalRanged.does = 'stonehearth_ace:loop_hunt_animal'
LoopHuntAnimalRanged.args = {
   target = Entity,                  -- the animal to hunt
}
LoopHuntAnimalRanged.priority = 1

function LoopHuntAnimalRanged:start_thinking(ai, entity, args)
   local weapon = stonehearth.combat:get_main_weapon(entity)

   if not weapon or not weapon:is_valid() then
      return
   end

   -- refetch every start_thinking as the set of actions may have changed
   local attack_types = stonehearth.combat:get_combat_actions(entity, 'stonehearth:combat:ranged_attacks')

   if not next(attack_types) then
      -- no ranged attacks
      return
   end

   ai:set_think_output()
end

local function can_attack_now(entity, target)
   local weapon = stonehearth.combat:get_main_weapon(entity)

   if not weapon or not weapon:is_valid() then
      return false
   end

   if radiant.entities.is_standing_on_ladder(entity) then
      return false
   end

   return stonehearth.combat:in_range_and_has_line_of_sight(entity, target, weapon)
end

function LoopHuntAnimalRanged:run(ai, entity, args)
   while radiant.entities.exists(args.target) do
      ai:execute('stonehearth:combat:wait_for_global_attack_cooldown')
      ai:execute('stonehearth:chase_entity_until_targetable', {
         target = args.target,
         grid_location_changed_cb = can_attack_now,
      })
      if radiant.entities.exists(args.target) then
         ai:execute('stonehearth:combat:attack_ranged', { target = args.target })
         ai:execute('stonehearth:combat:set_global_attack_cooldown')
      end
   end
end

return LoopHuntAnimalRanged
