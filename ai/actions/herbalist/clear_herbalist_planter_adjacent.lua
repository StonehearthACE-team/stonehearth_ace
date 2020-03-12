local Entity = _radiant.om.Entity

local ClearHerbalistPlanterAdjacent = radiant.class()
ClearHerbalistPlanterAdjacent.name = 'clear herbalist planter adjacent'
ClearHerbalistPlanterAdjacent.does = 'stonehearth_ace:clear_herbalist_planter_adjacent'
ClearHerbalistPlanterAdjacent.args = {
   planter = Entity,       -- the planter to clear
}
ClearHerbalistPlanterAdjacent.priority = 0

function ClearHerbalistPlanterAdjacent:start(ai, entity, args)
   local herbalist_planter = args.planter:get_component('stonehearth_ace:herbalist_planter')
   local status_text_key = 'stonehearth_ace:ai.actions.status_text.clear_herbalist_planter'
   ai:set_status_text_key(status_text_key, { target = args.planter })
end

function ClearHerbalistPlanterAdjacent:stop(ai, entity, args)
   local herbalist_planter = args.planter and args.planter:is_valid() and args.planter:get_component('stonehearth_ace:herbalist_planter')
   if herbalist_planter then
      herbalist_planter:stop_active_effect()
   end
end

function ClearHerbalistPlanterAdjacent:run(ai, entity, args)
   local planter = args.planter
   local planter_comp = planter:get_component('stonehearth_ace:herbalist_planter')
   if not planter_comp:is_plantable() or planter_comp:get_seed_uri() then
      ai:abort('planter is not currently clearable')
      return
   end
   
   radiant.entities.turn_to_face(entity, planter)
   local effect = planter_comp:get_planter_effect()
   planter_comp:run_planter_plant_effect()
   ai:execute('stonehearth:run_effect', { effect = effect })

   planter_comp:plant_crop(entity)

   radiant.events.trigger(entity, 'stonehearth_ace:clear_planter', {planter = planter})
end

return ClearHerbalistPlanterAdjacent
