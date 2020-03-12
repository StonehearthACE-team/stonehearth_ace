local Entity = _radiant.om.Entity
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local PlantHerbalistPlanterAdjacent = radiant.class()
PlantHerbalistPlanterAdjacent.name = 'plant herbalist planter adjacent'
PlantHerbalistPlanterAdjacent.does = 'stonehearth_ace:plant_herbalist_planter_adjacent'
PlantHerbalistPlanterAdjacent.args = {
   planter = Entity,       -- the planter to plant
}
PlantHerbalistPlanterAdjacent.priority = 0

function PlantHerbalistPlanterAdjacent:start(ai, entity, args)
   local herbalist_planter = args.planter:get_component('stonehearth_ace:herbalist_planter')
   local status_text_key = herbalist_planter and herbalist_planter:get_plant_status_text() or 'stonehearth_ace:ai.actions.status_text.plant_herbalist_planter'
   ai:set_status_text_key(status_text_key, { target = args.planter })
end

function PlantHerbalistPlanterAdjacent:stop(ai, entity, args)
   local herbalist_planter = args.planter and args.planter:is_valid() and args.planter:get_component('stonehearth_ace:herbalist_planter')
   if herbalist_planter then
      herbalist_planter:stop_active_effect()
   end
end

function PlantHerbalistPlanterAdjacent:run(ai, entity, args)
   local planter = args.planter
   local planter_comp = planter:get_component('stonehearth_ace:herbalist_planter')
   if not planter_comp:is_plantable() then
      ai:abort('planter is not currently plantable')
      return
   end
   
   local seed = radiant.entities.remove_carrying(entity)
   local req_seed = planter_comp:get_seed_uri()
   if not seed:is_valid() or entity_forms.get_root_entity(seed):get_uri() ~= req_seed then
      ai:abort('not carrying the right seed!')
      return
   end

   radiant.entities.turn_to_face(entity, planter)
   local effect = planter_comp:get_planter_effect()
   planter_comp:run_planter_plant_effect()
   ai:execute('stonehearth:run_effect', { effect = effect })

   planter_comp:plant_crop(entity)
   radiant.entities.destroy_entity(seed)

   radiant.events.trigger(entity, 'stonehearth_ace:plant_planter', {planter = planter})
end

return PlantHerbalistPlanterAdjacent
