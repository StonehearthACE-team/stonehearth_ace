local Entity = _radiant.om.Entity

local TrainBetweenAttacks = radiant.class()

TrainBetweenAttacks.name = 'training'
TrainBetweenAttacks.does = 'stonehearth_ace:train_between_attacks'
TrainBetweenAttacks.args = {
   target = Entity
}
TrainBetweenAttacks.priority = 0

function TrainBetweenAttacks:start_thinking(ai, entity, args)
   self._effect = stonehearth.combat:get_weapon_idle_data(entity) or 'combat_1h_idle'
   ai:set_think_output()
end

function TrainBetweenAttacks:run(ai, entity, args)
   radiant.entities.turn_to_face(entity, args.target)
   
   ai:execute('stonehearth:bump_allies', {
      distance = 2,
   })

   ai:execute('stonehearth:run_effect_timed', {
      effect = self._effect,
      facing_entity = args.target,
      duration = '1m+1m'
   })
end

return TrainBetweenAttacks