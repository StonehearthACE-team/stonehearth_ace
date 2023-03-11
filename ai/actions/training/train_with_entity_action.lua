local Entity = _radiant.om.Entity
local TrainWithEntity = radiant.class()
TrainWithEntity.name = 'train with entity'
TrainWithEntity.does = 'stonehearth_ace:train_with_entity'
TrainWithEntity.args = {
   target = Entity
}
TrainWithEntity.priority = 0

function TrainWithEntity:start(ai, entity, args)
   ai:set_status_text_key('stonehearth_ace:ai.actions.status_text.training', { target = args.target })
end

local ai = stonehearth.ai
return ai:create_compound_action(TrainWithEntity)
         :execute('stonehearth_ace:train_attack', { target = ai.ARGS.target })
