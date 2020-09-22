local Entity = _radiant.om.Entity
local rng = _radiant.math.get_default_rng()
local all_crop_data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter:crops')

local TendHerbalistPlanterAdjacent = radiant.class()
TendHerbalistPlanterAdjacent.name = 'tend herbalist planter adjacent'
TendHerbalistPlanterAdjacent.does = 'stonehearth_ace:tend_herbalist_planter_adjacent'
TendHerbalistPlanterAdjacent.args = {
   planter = Entity,       -- the planter to tend
}
TendHerbalistPlanterAdjacent.priority = 0

function TendHerbalistPlanterAdjacent:start(ai, entity, args)
   local status_text_key = 'stonehearth_ace:ai.actions.status_text.tend_herbalist_planter'
   ai:set_status_text_key(status_text_key, { target = args.planter })
end

function TendHerbalistPlanterAdjacent:run(ai, entity, args)
   local planter = args.planter
   local planter_comp = planter:get_component('stonehearth_ace:herbalist_planter')
   if not planter_comp:is_tendable() then
      ai:abort('planter is not currently tendable')
   else
      radiant.entities.turn_to_face(entity, planter)
      local effects = stonehearth.constants.herbalist_planters.tend_effects or {'fiddle'}
      local effect = effects[rng:get_int(1, #effects)]
      radiant.log.write('stonehearth_ace', 0, 'trying to use tend effect "' .. tostring(effect) .. '"...')
      ai:execute('stonehearth:run_effect', { effect = effect })

      planter_comp:tend_to_crop(entity)

      radiant.events.trigger(entity, 'stonehearth_ace:interact_herbalist_planter', {type = 'tend_planter', planter = planter})
   end
end

return TendHerbalistPlanterAdjacent
