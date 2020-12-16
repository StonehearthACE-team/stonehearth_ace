local Entity = _radiant.om.Entity

local LoopHuntAnimalMelee = radiant.class()

LoopHuntAnimalMelee.name = 'keep hunting this animal'
LoopHuntAnimalMelee.does = 'stonehearth_ace:loop_hunt_animal'
LoopHuntAnimalMelee.args = {
   target = Entity,                  -- the animal to hunt
}
LoopHuntAnimalMelee.priority = 0.5

function LoopHuntAnimalMelee:start_thinking(ai, entity, args)
   local weapon = stonehearth.combat:get_main_weapon(entity)
   if weapon == nil or not weapon:is_valid() then
      log:warning('%s has no weapon', entity)
      return
   end
   local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
   radiant.verify(weapon_data, "entity %s has no stonehearth:combat:weapon_data but is equipped as a melee weapon", weapon:get_uri())

   ai:set_think_output({})
end

function LoopHuntAnimalMelee:run(ai, entity, args)
   while radiant.entities.exists(args.target) do
      ai:execute('stonehearth:combat:attack', {
         target = args.target,
      })
   end
end

return LoopHuntAnimalMelee