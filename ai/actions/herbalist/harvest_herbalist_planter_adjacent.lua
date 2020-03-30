local Entity = _radiant.om.Entity

local HarvestHerbalistPlanterAdjacent = radiant.class()
HarvestHerbalistPlanterAdjacent.name = 'harvest herbalist planter adjacent'
HarvestHerbalistPlanterAdjacent.does = 'stonehearth_ace:harvest_herbalist_planter_adjacent'
HarvestHerbalistPlanterAdjacent.args = {
   planter = Entity,       -- the planter to harvest
   owner_player_id = {
      type = 'string',
      default = stonehearth.ai.NIL,
   },
}
HarvestHerbalistPlanterAdjacent.priority = 0

function HarvestHerbalistPlanterAdjacent:start(ai, entity, args)
   local herbalist_planter = args.planter:get_component('stonehearth_ace:herbalist_planter')
   local status_text_key = herbalist_planter and herbalist_planter:get_harvest_status_text() or 'stonehearth_ace:ai.actions.status_text.harvest_herbalist_planter'
   ai:set_status_text_key(status_text_key, { target = args.planter })
end

function HarvestHerbalistPlanterAdjacent:stop(ai, entity, args)
   local herbalist_planter = args.planter and args.planter:is_valid() and args.planter:get_component('stonehearth_ace:herbalist_planter')
   if herbalist_planter then
      herbalist_planter:stop_active_effect()
   end
end

function HarvestHerbalistPlanterAdjacent:run(ai, entity, args)
   local planter = args.planter
   local planter_comp = planter:get_component('stonehearth_ace:herbalist_planter')
   if not planter_comp:is_harvestable() then
      ai:abort('planter is not currently harvestable')
   else
      radiant.entities.turn_to_face(entity, planter)
      local effect = planter_comp:get_harvester_effect()
      planter_comp:run_planter_harvest_effect()
      ai:execute('stonehearth:run_effect', { effect = effect })

      local products = planter_comp:create_products(entity)
      radiant.events.trigger(entity, 'stonehearth_ace:interact_herbalist_planter', {type = 'harvest_planter', planter = planter, products = products})
		
		if planter_comp:get_additional_products() then
			local location = radiant.entities.get_world_grid_location(entity)
         planter_comp:spawn_additional_items(entity, location)
		end
   end
end

return HarvestHerbalistPlanterAdjacent
