local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local resources_lib = require 'stonehearth_ace.lib.resources.resources_lib'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'

local transform_lib = {}

local log = radiant.log.create_logger('transform_lib')

-- largely constructed from the original evolve_component:evolve() function
function transform_lib.transform(entity, transform_source, into_uri, options)
   if type(into_uri) == 'table' then
      -- allow for tables that are just lists of uris, and also for uri properties with weight values
      if type(into_uri[1]) == 'string' then
         into_uri = into_uri[rng:get_int(1, #into_uri)]
      else
         local items = WeightedSet(rng)
         for uri, weight in pairs(into_uri) do
            items:add(uri, weight)
         end
         into_uri = items:choose_random()
      end
   end

   options = options or {}
   if options.check_script then
      local script = radiant.mods.load_script(options.check_script)
      if script and not script.should_transform(entity, transform_source, into_uri, options) then
         return false
      end
   end

   if radiant.entities.is_entity_suspended(entity) then
      return false
   end

   -- if the entity is mounted and/or has something mounted on it, dismount before transforming
   local mount_component = entity:get_component('stonehearth:mount')
   if mount_component then
      mount_component:dismount()
   end

   local parent = radiant.entities.get_parent(entity) or radiant.entities.get_root_entity()
   mount_component = parent and parent:get_component('stonehearth:mount')
   if mount_component then
      mount_component:dismount()
      parent = radiant.entities.get_parent(entity) or radiant.entities.get_root_entity()
   end

   local location = radiant.entities.get_world_grid_location(entity)
   local local_location = radiant.entities.get_location_aligned(entity)
   local facing = radiant.entities.get_facing(entity)

   local root_form, iconic_form = entity_forms_lib.get_forms(entity)
   local transformed_form

   if into_uri and into_uri ~= '' then
      --Create the transformed entity and put it on the ground
      transformed_form = radiant.entities.create_entity(into_uri, { owner = options.transformer_entity or entity})
      -- set the facing so that is_standable properly considers a rotated collision region
      radiant.entities.turn_to(transformed_form, facing)
      
      item_quality_lib.copy_quality(entity, transformed_form)

      radiant.entities.set_player_id(transformed_form, entity)

      -- Have to remove entity because it can collide with transformed form
      -- If its parent is a structure, we want to remove it from that structure and place the new one on that structure
      radiant.entities.remove_child(parent, entity)
      radiant.entities.move_to_grid_aligned(entity, Point3.zero)
		
		local aquatic_object = entity:get_component('stonehearth_ace:aquatic_object')
      if location and not radiant.terrain.is_standable(transformed_form, location) and not aquatic_object then
         -- If cannot transform because the transformed form will not fit in the current location, just return (evolve will try again after a new timer)
         transform_lib.place_entity_at_location(entity, parent, local_location, facing)
         radiant.entities.destroy_entity(transformed_form)
         return false
      end

      local player_id = radiant.entities.get_player_id(entity)

      -- if the original entity is part of the player's inventory, add the transformed item to the inventory
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory and inventory:contains_item(entity) then
         inventory:add_item(transformed_form)
      end

      radiant.events.trigger(entity, 'stonehearth_ace:transform:pre_transform', {transformed_form = transformed_form, transform_source = transform_source, options = options})

      local owner_component = entity:get_component('stonehearth:ownable_object')
      local owner = owner_component and owner_component:get_owner()
      if owner then
         local transformed_owner_component = transformed_form:get_component('stonehearth:ownable_object')
         if transformed_owner_component then
            -- need to remove the original's owner so that destroying it later doesn't mess things up with the new entity's ownership
            -- but if it's a medic patient bed (or some other proxy owner), we want to transfer (duplicate) the proxy owner
            -- likewise if it's reserved for travelers
            local owner_proxy = owner:get_component('stonehearth_ace:owner_proxy')
            local new_owner_proxy
            local traveler_reservation = owner:get_component('stonehearth:traveler_reservation')

            if owner_proxy then
               local new_owner = radiant.entities.create_entity(owner:get_uri())
               new_owner_proxy = new_owner:add_component('stonehearth_ace:owner_proxy')
               new_owner_proxy:set_type(owner_proxy:get_type())
            end

            owner_component:set_owner(nil)

            if new_owner_proxy then
               new_owner_proxy:track_reservation(transformed_form)
            elseif traveler_reservation then
               traveler_reservation:unassign_traveler()
               stonehearth.traveler:reserve_for_travelers(transformed_form)
               local traveler_component = owner:get_component('stonehearth:traveler')
               if traveler_component then
                  traveler_component:update_bed(transformed_form)
               end
            else
               transformed_owner_component:set_owner(owner)
            end
         end
      end
		
		-- If the transformed entity is a storage, transfer the contents (regardless of capacity)
		local storage_component = entity:get_component('stonehearth:storage')
		if storage_component then 
         if options.dump_storage then
            storage_component:drop_all(location)
         else
            local transformed_storage_component = transformed_form:get_component('stonehearth:storage')			
            if transformed_storage_component then
               -- apply the same storage filter on the transformed entity
               local storage_filter = storage_component:get_filter()
               if storage_filter then
                  transformed_storage_component:set_filter(storage_filter)
               end
               -- transfer the contents
               local storage = storage_component:get_items()
               for id, item in pairs(storage) do
                  if item and item:is_valid() then
                     local removed_item = storage_component:remove_item(id)
                     transformed_storage_component:add_item(removed_item, true)
                  end
               end
            end
         end
		end

      local unit_info = entity:get_component('stonehearth:unit_info')
      local custom_name = unit_info and unit_info:get_custom_name()
      if custom_name then
         local transformed_unit_info = transformed_form:get_component('stonehearth:unit_info')
         if transformed_unit_info then
            transformed_unit_info:set_custom_name(custom_name, unit_info:get_custom_data())
         end
      end

      local pet_component = entity:get_component('stonehearth:pet')
      if pet_component then
         local pet_owner = pet_component:get_owner()
         local pet_name = radiant.entities.get_custom_name(entity) or radiant.entities.get_display_name(entity)
         if pet_owner and pet_name then
            local transformed_pet_component = transformed_form:add_component('stonehearth:pet')
            if transformed_pet_component then
               transformed_pet_component:convert_to_pet(player_id)
               transformed_pet_component:set_owner(pet_owner)
               radiant.entities.set_custom_name(transformed_form, pet_name)
            end
         end
      end

      local pic_key = 'stonehearth_ace:periodic_interaction'
      local periodic_interaction_component = entity:get_component('stonehearth_ace:periodic_interaction')
      if periodic_interaction_component then
         local pic_owner = periodic_interaction_component:get_current_owner()
         local pic_mode = periodic_interaction_component:get_current_mode()
         if pic_owner or pic_mode then
            local transformed_periodic_interaction_component = transformed_form:get_component('stonehearth_ace:periodic_interaction')
            if transformed_periodic_interaction_component then
               if pic_owner then
                  transformed_periodic_interaction_component:set_owner(pic_owner)
               end
               if pic_mode then
                  transformed_periodic_interaction_component:select_mode(pic_mode)
               end
            else
               transformed_form:add_component('stonehearth_ace:transform'):store_component_data(pic_key, {
                  owner = pic_owner,
                  mode = pic_mode,
               })
            end
         end
      else
         local transform_component = entity:get_component('stonehearth_ace:transform')
         local pic_data = transform_component and transform_component:get_component_data(pic_key)
         if pic_data then
            local transformed_periodic_interaction_component = transformed_form:add_component('stonehearth_ace:periodic_interaction')
            if transformed_periodic_interaction_component then
               if pic_data.owner then
                  transformed_periodic_interaction_component:set_owner(pic_data.owner)
               end
               if pic_data.mode then
                  transformed_periodic_interaction_component:select_mode(pic_data.mode)
               end
            else
               transformed_form:add_component('stonehearth_ace:transform'):store_component_data(pic_key, {
                  owner = pic_data.owner,
                  mode = pic_data.mode,
               })
            end
         end
      end

      local transformed_form_data = radiant.entities.get_entity_data(transformed_form, 'stonehearth:evolve_data')
      if transformed_form_data and transform_source == 'stonehearth:evolve' then
         -- Ensure the transformed form also has the evolve component if it will evolve
         -- but first check if it should get "stunted"
         if not transformed_form_data.stunted_chance or rng:get_real(0, 1) > transformed_form_data.stunted_chance then
            transformed_form:add_component('stonehearth:evolve')
            -- if it allows for manually stunting growth, make sure the transform option is set up
            local modifiers = radiant.entities.get_entity_data(transformed_form, 'stonehearth_ace:evolve_modifiers')
            if modifiers and modifiers.allow_manual_stunting then
               transformed_form:add_component('stonehearth_ace:transform'):reconsider_commands()
            end
         end
      end

      local crop = entity:get_component('stonehearth:crop')
      if crop then
         local transformed_crop = transformed_form:add_component('stonehearth:crop')
         transformed_crop:copy_data(crop)
         transformed_crop:update_post_harvest_crop()
         transformed_form:remove_component('stonehearth_ace:stump')  -- don't want a stump after it gets harvested
         crop:set_field()  -- we set the old crop to nil so it won't alert the field when it gets destroyed
      end

      local output = entity:get_component('stonehearth_ace:output')
      if output then
         local transformed_output = transformed_form:add_component('stonehearth_ace:output')
         transformed_output:set_parent_output(output:get_parent_output())
         for id, input in pairs(output:get_inputs()) do
            transformed_output:add_input(input)
         end
      end

      local mob = entity:get_component('mob')
      if mob and mob:get_ignore_gravity() then
         transformed_form:add_component('mob'):set_ignore_gravity(true)
      end

      if location then
         transform_lib.place_entity_at_location(transformed_form, parent, local_location, facing)

         if options.auto_harvest_key then
            local stage_data = radiant.entities.get_entity_data(transformed_form, 'stonehearth_ace:stage_data')
            local stage = stage_data and stage_data.current_stage
            if options.auto_harvest_key == stage then
               resources_lib.request_auto_harvest(transformed_form, true)
            else
               local transform_comp = transformed_form:add_component('stonehearth_ace:transform'):add_option_overrides({auto_harvest_key = options.auto_harvest_key})
            end
         else
            resources_lib.request_auto_harvest(transformed_form, options.auto_harvest)
         end
      end

      -- check if the current entity is the town's banner or hearth; if so, change it to this one
      local town = stonehearth.town:get_town(entity)
      if town then
         if town:get_banner() == entity then
            town:set_banner(transformed_form)
         end
         if town:get_hearth() == entity then
            town:set_hearth(transformed_form)
         end
      end
   end

   local transform_effect = options.transform_effect
   if location and transform_effect then
      local proxy
      if not transformed_form then
         proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'spawn effect effect anchor' })
         radiant.terrain.place_entity_at_exact_location(proxy, location)
      end

      local effect = radiant.effects.run_effect(transformed_form or proxy, transform_effect)
      effect:set_finished_cb(function()
         if proxy then
            radiant.entities.destroy_entity(proxy)
         end
      end)
   end

   if options.transform_script then
      local script = radiant.mods.load_script(options.transform_script)
      script.transform(entity, transformed_form, transform_source, options)
   end

   if options.transform_event then
      options.transform_event(transformed_form)
   end

   -- option to kill on transform instead of destroying (e.g., if you need to have it drop loot or trigger the killed event)
   if options.kill_entity then
      local loot_drops_component = entity:get_component('stonehearth:loot_drops')
      if loot_drops_component and options.transformer_entity then
         local player_id = radiant.entities.get_player_id(options.transformer_entity)
         loot_drops_component:set_auto_loot_player_id(player_id)
      end
      radiant.entities.kill_entity(entity, {location = location})
   elseif options.undeploy_entity and iconic_form and location then
      -- option to undeploy, but only use it if there's an iconic form
      local output_options = {
         output = options.transformer_entity,
         spill_fail_items = true,
      }
      radiant.entities.output_spawned_items({[iconic_form:get_id()] = iconic_form}, location, 1, 2, output_options)
   elseif options.destroy_entity ~= false then
      radiant.entities.destroy_entity(entity)
   elseif options.remove_components then
      for _, component in ipairs(options.remove_components) do
         entity:remove_component(component)
      end
      local transform_comp = entity:get_component('stonehearth_ace:transform')
      if transform_comp then
         transform_comp:reconsider_commands()
      end
   end
	
	if transformed_form and options.model_variant then
      local render_info = transformed_form:add_component('render_info')
		render_info:set_model_variant(options.model_variant)
   end

   return transformed_form
end

function transform_lib.place_entity_at_location(entity, parent, location, facing)
   if facing then
      entity:add_component('mob'):turn_to(facing)
   end
   radiant.entities.add_child(parent, entity, location)
end

return transform_lib