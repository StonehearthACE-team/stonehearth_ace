local Entity = _radiant.om.Entity

local LoopHuntAnimal = radiant.class()

LoopHuntAnimal.name = 'keep hunting this animal'
LoopHuntAnimal.does = 'stonehearth_ace:loop_hunt_animal'
LoopHuntAnimal.args = {
   target = Entity,                  -- the animal to hunt
}
LoopHuntAnimal.priority = 0

local function is_attack_cooled_down(entity)
   local state = stonehearth.combat:get_combat_state(entity)
   return not state:in_cooldown('global_attack_recovery')
end

local ai = stonehearth.ai
return ai:create_compound_action(LoopHuntAnimal)
      :loop({
         name = 'hunt animal',
         break_timeout = 2000,
         break_condition = function(ai, entity, args)
            return not radiant.entities.exists(args.target)
         end
      })
         :execute('stonehearth:chase_entity', {
            target = ai.UP.ARGS.target,
            grid_location_changed_cb = is_attack_cooled_down,
         })
         :execute('stonehearth:combat:attack', { target = ai.UP.ARGS.target })
         :execute('stonehearth:combat:set_global_attack_cooldown')
      :end_loop()
