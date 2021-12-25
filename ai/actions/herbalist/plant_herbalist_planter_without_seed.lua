local Entity = _radiant.om.Entity

local PlantHerbalistPlanterWithoutSeed = radiant.class()

PlantHerbalistPlanterWithoutSeed.name = 'plant herbalist planter'
PlantHerbalistPlanterWithoutSeed.does = 'stonehearth_ace:plant_herbalist_planter'
PlantHerbalistPlanterWithoutSeed.args = {
   planter = Entity,    -- the planter that needs to be planted in
   seed_uri = {         -- the uri of the seed needed for planting
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
PlantHerbalistPlanterWithoutSeed.priority = 0

function PlantHerbalistPlanterWithoutSeed:start_thinking(ai, entity, args)
   if not args.seed_uri then
      ai:set_think_output({})
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PlantHerbalistPlanterWithoutSeed)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth_ace:plant_herbalist_planter_adjacent', {
            planter = ai.ARGS.planter
         })
