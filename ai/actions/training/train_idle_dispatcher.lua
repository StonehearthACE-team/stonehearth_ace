local Entity = _radiant.om.Entity
local TrainIdleDispatcher = radiant.class()
TrainIdleDispatcher.name = 'train combat idle dispatcher'
TrainIdleDispatcher.does = 'stonehearth_ace:train_attack'
TrainIdleDispatcher.args = {
    target = Entity
}
TrainIdleDispatcher.priority = 0.15

local ai = stonehearth.ai
return ai:create_compound_action(TrainIdleDispatcher)
         :execute('stonehearth:go_toward_location', { destination = ai.ARGS.target })
         :execute('stonehearth:combat:idle', { target = ai.ARGS.target })

