local Entity = _radiant.om.Entity

local PlantHerbalistPlanter = radiant.class()

PlantHerbalistPlanter.name = 'plant herbalist planter'
PlantHerbalistPlanter.does = 'stonehearth_ace:plant_herbalist_planter'
PlantHerbalistPlanter.args = {
   planter = Entity,    -- the planter that needs to be planted in
   seed_uri = {         -- the uri of the seed needed for planting
      type = 'string',
      default = stonehearth.ai.NIL,
   }
}
PlantHerbalistPlanter.priority = 0

function PlantHerbalistPlanter:start_thinking(ai, entity, args)
   if args.seed_uri then
      ai:set_think_output({})
   end
end

local seed_rating_fn = function(item)
   return radiant.entities.get_item_quality(item) / 3
end

local ai = stonehearth.ai
return ai:create_compound_action(PlantHerbalistPlanter)
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:pickup_item_with_uri', {
            uri = ai.ARGS.seed_uri,
            rating_fn = seed_rating_fn
         })
         :execute('stonehearth:goto_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth:reserve_entity', { entity = ai.ARGS.planter })
         :execute('stonehearth_ace:plant_herbalist_planter_adjacent', {
            planter = ai.ARGS.planter
         })
