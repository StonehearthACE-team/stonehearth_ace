local Entity = _radiant.om.Entity

local HuntAnimalMelee = radiant.class()

HuntAnimalMelee.name = 'keep hunting this animal'
HuntAnimalMelee.does = 'stonehearth_ace:hunt_animal'
HuntAnimalMelee.args = {
   target = Entity,                  -- the animal to hunt
}
HuntAnimalMelee.priority = 0.5

function HuntAnimalMelee:start_thinking(ai, entity, args)
   local weapon = stonehearth.combat:get_main_weapon(entity)
   if weapon == nil or not weapon:is_valid() then
      log:warning('%s has no weapon', entity)
      return
   end
   local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
   radiant.verify(weapon_data, "entity %s has no stonehearth:combat:weapon_data but is equipped as a melee weapon", weapon:get_uri())

   ai:set_think_output({})
end

local ai = stonehearth.ai
return ai:create_compound_action(HuntAnimalMelee)
         :execute('stonehearth:combat:attack', {
            target = ai.ARGS.target,
         })
