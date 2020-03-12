local Entity = _radiant.om.Entity

local PlantHerbalistPlanter = radiant.class()

PlantHerbalistPlanter.name = 'plant herbalist planter'
PlantHerbalistPlanter.does = 'stonehearth_ace:plant_herbalist_planter'
PlantHerbalistPlanter.args = {
   planter = Entity,    -- the planter that needs to be planted in
   seed_uri = 'string'  -- the uri of the seed needed for planting
}
PlantHerbalistPlanter.priority = 0

local ai = stonehearth.ai
return ai:create_compound_action(PlantHerbalistPlanter)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:pickup_item_with_uri', {
            uri = ai.ARGS.seed_uri
         })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth_ace:plant_herbalist_planter_adjacent', {
            planter = ai.ARGS.planter
         })
