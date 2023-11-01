local AceHarvestRenewableResourceAdjacent = class()

function AceHarvestRenewableResourceAdjacent:run(ai, entity, args)
   local resource = args.resource
   local id = resource:get_id()

   --Fiddle with the bush and pop the basket
   local factory = resource:get_component('stonehearth:renewable_resource_node')
   if not factory:is_harvestable() then
      ai:abort('resource is not currently harvestable')
   end

   if factory then
      radiant.entities.turn_to_face(entity, resource)

      --ACE Addition starts here
      local harvested_effect = factory:get_harvested_effect()
      if harvested_effect then
         radiant.effects.run_exact_effect(resource, harvested_effect)
      end

      local effect = factory:get_harvester_effect()
      ai:execute('stonehearth:run_effect', { effect = effect })

      local location = radiant.entities.get_world_grid_location(entity)
      local spawned_item = factory:spawn_resource(entity, location, args.owner_player_id)

      if spawned_item then
         local spawned_item_name = radiant.entities.get_display_name(spawned_item)
         local substitution_values = {}
         substitution_values['gather_target'] = spawned_item_name
         radiant.events.trigger_async(stonehearth.personality, 'stonehearth:journal_event',
                                     {entity = entity, description = 'gathering_supplies', substitutions = substitution_values})

         radiant.events.trigger_async(entity, 'stonehearth:gather_renewable_resource',
            {harvested_target = resource, spawned_item = spawned_item})
      end
   end
end

return AceHarvestRenewableResourceAdjacent
