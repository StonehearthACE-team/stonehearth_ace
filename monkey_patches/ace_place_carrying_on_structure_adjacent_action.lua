local AcePlaceItemOnStructureAdjacent = radiant.class()

function AcePlaceItemOnStructureAdjacent:run(ai, entity, args)
   local ghost = args.ghost
   local options = ghost:get_component('stonehearth:ghost_form')
                           :get_placement_info()
   if not options then
      ai:abort('placement cancelled before arriving?')
   end

   local iconic_uri = options.iconic_uri
   local carrying = radiant.entities.get_carrying(entity)
   if not carrying then
      ai:abort('Not actually carrying anything.')  -- Observed in the wild, but no clear repro
   end
   if carrying:get_uri() ~= iconic_uri then
      ai:abort('carrying wrong item to place on structure adjacent.')
   end
   local iconic_component = carrying:get_component('stonehearth:iconic_form')
   local root_entity = iconic_component:get_root_entity()
   local requested_quality = ghost:get_component('stonehearth:ghost_form'):get_requested_quality()
   if requested_quality and radiant.entities.get_item_quality(root_entity) ~= requested_quality then
      ai:abort('carrying wrong item quality to place on structure adjacent.')
   end
   if not (options.structure and options.structure:is_valid() and radiant.entities.get_world_location(options.structure)) then
      ai:unprotect_argument(ghost)
      radiant.entities.destroy_entity(ghost)
      ai:abort('supporting structure no longer exists')
   end

   if not options.ignore_envelope then
      local rcs = root_entity:get('region_collision_shape')
      if rcs then
         local bregion = rcs:get_region()
         if bregion then
            local region_w = bregion:get():translated(options.location)
            local es = radiant.terrain.get_entities_in_region(region_w, function(e)
                  return e:get_uri() == 'stonehearth:build2:entities:envelope'
               end)
            if not radiant.empty(es) then
               local town = stonehearth.town:get_town(root_entity)
               town:remove_town_tasks_on_item(root_entity)
               town:remove_town_tasks_on_item(carrying)
               ai:unprotect_argument(ghost)
               radiant.entities.destroy_entity(ghost)
               ai:abort('tried placing an item in a building envelope')
            end
         end
      end
   end

   assert(ghost:is_valid())
   assert(root_entity:is_valid())

   local placement_effect = 'work'
   local placement_data = radiant.entities.get_entity_data(root_entity, 'stonehearth:placement')
   if placement_data and placement_data.effect then
      placement_effect = placement_data.effect
   end

   ai:execute('stonehearth:turn_to_face_entity', { entity = ghost })
   ai:execute('stonehearth:run_effect', { effect = placement_effect })
   radiant.effects.run_effect(entity, 'stonehearth:effects:place_item')

   radiant.entities.remove_carrying(entity)
   
   if radiant.entities.exists_in_world(root_entity) then
      -- We are trying to place an iconic, but its root form is already in the world. Something is terribly wrong.
      -- Fix the inconsistency by aborting now (AFTER we've removed the iconic from the world in remove_carrying()).
      ai:abort('root already in the world; removed iconic from world')  -- Observed in the wild, but no clear repro.
   end
   
   local structure = options.structure
   local entity_forms = root_entity:get_component('stonehearth:entity_forms')
   if entity_forms and entity_forms:must_parent_to_terrain() then
      structure = radiant._root_entity
   end
   radiant.entities.add_child(structure, root_entity)

   local position = options.location - radiant.entities.get_world_grid_location(structure)
   root_entity:add_component('mob')
                        :move_to_grid_aligned(position)
                        :turn_to(options.rotation)

   local destination_comp = root_entity:get_component('destination')
   if destination_comp then
      destination_comp:set_region(destination_comp:get_region())
   end
   local rcs_comp = root_entity:get_component('region_collision_shape')
   if rcs_comp then
      rcs_comp:set_region(rcs_comp:get_region())
   end

   if options.ignore_gravity then
      root_entity:get_component('mob'):set_ignore_gravity(true)
   end

   radiant.verify(ghost:is_valid(), "Ghost is no longer valid after putting down the item")

   local event_args = {ghost_id = ghost:get_id(), placed_item = root_entity, structure = structure, options = options}
   radiant.events.trigger_async(entity, 'stonehearth:item_placed', event_args)
   radiant.events.trigger(ghost, 'stonehearth:item_placed_on_structure', event_args)
   -- now nuke the ghost!  this must be last, as it may terminate the task
   ai:unprotect_argument(ghost)
   radiant.entities.destroy_entity(ghost)
end

return AcePlaceItemOnStructureAdjacent
