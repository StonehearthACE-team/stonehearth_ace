local rng = _radiant.math.get_default_rng()
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local transform_lib = {}

-- largely constructed from the original evolve_component:evolve() function
function transform_lib.transform(entity, transformer, into_uri, options)
   options = options or {}
   if options.check_script then
      local script = radiant.mods.require(options.check_script)
      if script and not script.should_transform(entity, transformer, into_uri, options) then
         return false
      end
   end

   if radiant.entities.is_entity_suspended(entity) then
      return false
   end

   local location = radiant.entities.get_world_grid_location(entity)
   local facing = radiant.entities.get_facing(entity)

   if type(into_uri) == 'table' then
      into_uri = into_uri[rng:get_int(1, #into_uri)]
   end   

   local transformed_form

   if into_uri and into_uri ~= '' then
      --Create the transformed entity and put it on the ground
      transformed_form = radiant.entities.create_entity(into_uri, { owner = entity})
      
      item_quality_lib.copy_quality(entity, transformed_form)

      radiant.entities.set_player_id(transformed_form, entity)

      -- Have to remove entity because it can collide with transformed form
      radiant.terrain.remove_entity(entity)
      if location and not radiant.terrain.is_standable(transformed_form, location) then
         -- If cannot transform because the transformed form will not fit in the current location, just return (evolve will try again after a new timer)
         radiant.terrain.place_entity_at_exact_location(entity, location, { force_iconic = false, facing = facing })
         radiant.entities.destroy_entity(transformed_form)
         return false
      end

      local owner_component = entity:get_component('stonehearth:ownable_object')
      local owner = owner_component and owner_component:get_owner()
      if owner then
         local transformed_owner_component = transformed_form:get_component('stonehearth:ownable_object')
         if transformed_owner_component then
            -- need to remove the original's owner so that destroying it later doesn't mess things up with the new entity's ownership
            owner_component:set_owner(nil)
            transformed_owner_component:set_owner(owner)
         end
      end

      local unit_info = entity:get_component('stonehearth:unit_info')
      local custom_name = unit_info and unit_info:get_custom_name()
      if custom_name then
         local transformed_unit_info = transformed_form:get_component('stonehearth:unit_info')
         if transformed_unit_info then
            transformed_unit_info:set_custom_name(custom_name)
         end
      end

      local transformed_form_data = radiant.entities.get_entity_data(transformed_form, 'stonehearth:evolve_data')
      if transformed_form_data and transformer == 'stonehearth:evolve' then
         -- Ensure the transformed form also has the evolve component if it will evolve
         -- but first check if it should get "stunted"
         if not transformed_form_data.stunted_chance or rng:get_real(0, 1) > transformed_form_data.stunted_chance then
            transformed_form:add_component('stonehearth:evolve')
         end
      end

      local mob = entity:get_component('mob')
      if mob and mob:get_ignore_gravity() then
         transformed_form:add_component('mob'):set_ignore_gravity(true)
      end

      if location then
         radiant.terrain.place_entity_at_exact_location(transformed_form, location, { force_iconic = false, facing = facing } )

         local transform_effect = options.transform_effect
         if transform_effect then
            radiant.effects.run_effect(transformed_form, transform_effect)
         end

         if options.auto_harvest then
            local renewable_resource_node = transformed_form:get_component('stonehearth:renewable_resource_node')
            local resource_node = transformed_form:get_component('stonehearth:resource_node')

            if renewable_resource_node and renewable_resource_node:is_harvestable() then
               renewable_resource_node:request_harvest(entity:get_player_id())
            elseif resource_node then
               resource_node:request_harvest(entity:get_player_id())
            end
         end
      end
   end

   if options.transform_script then
      local script = radiant.mods.require(options.transform_script)
      script.transform(entity, transformed_form, transformer)
   end

   if options.transform_event then
      options.transform_event(transformed_form)
   end

   -- option to kill on transform instead of destroying (e.g., if you need to have it drop loot or trigger the killed event)
   if options.kill_entity then
      radiant.entities.kill_entity(entity)
   elseif options.destroy_entity ~= false then
      radiant.entities.destroy_entity(entity)
   end

   return transformed_form
end

return transform_lib