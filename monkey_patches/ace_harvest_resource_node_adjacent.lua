local AceHarvestResourceNodeAdjacent = class()

function AceHarvestResourceNodeAdjacent:run(ai, entity, args)
   local node = args.node
   local node_id = node:get_id()
   local factory = node:get_component('stonehearth:resource_node')

   if not factory:is_harvestable() then
      ai:abort('resource is not currently harvestable')
   end

   if factory then
      radiant.entities.turn_to_face(entity, node)
      ai:unprotect_argument(node)
      --get the thought+description before harvesting, because the factory (resource_node_component) disappears when the node does...
      local thought = factory:get_harvester_thought()
      local description = factory:get_description()

      local location = radiant.entities.get_world_grid_location(entity)
      repeat
         local effect = factory:get_harvester_effect()
         ai:execute('stonehearth:run_effect', { effect = effect})

         factory:spawn_resource(entity, location, args.owner_player_id)
      until not node:is_valid()

      if thought then
         radiant.entities.add_thought(entity, thought)
      end

      --radiant.events.trigger_async(entity, 'stonehearth:gather_resource', {harvested_target = node})
      radiant.events.trigger_async(stonehearth.personality, 'stonehearth:journal_event',
                                   {entity = entity, description = description})
   end
end

return AceHarvestResourceNodeAdjacent
