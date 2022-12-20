local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local log = radiant.log.create_logger('client_entities')

local ace_client_entities = {}

ace_client_entities._ace_old_create_entity = radiant.entities.create_entity
function ace_client_entities.create_entity(ref, options)
   local entity = ace_client_entities._ace_old_create_entity(ref, options)
   if entity then
      local create_entity_data = radiant.entities.get_entity_data(entity, 'stonehearth_ace:create_entity')
      local model_variant = options and options.model_variant
      if model_variant then
         entity:add_component('render_info'):set_model_variant(model_variant)
      elseif create_entity_data and create_entity_data.assign_random_model_variant then
         -- if there's a default assigned, try to just find the corresponding model variant from that
         local variant_to_set = radiant.entities.get_model_variant(entity, true)
         if not variant_to_set or variant_to_set == '' or variant_to_set == 'default' then
            local model_variants = radiant.entities.get_component_data(entity, 'model_variants')
            local variants = WeightedSet(rng)
            for id, variant in pairs(model_variants) do
               if id ~= 'default' then
                  variants:add(id, 1)
               end
            end
            variant_to_set = variants:choose_random()
         end
         entity:add_component('render_info'):set_model_variant(variant_to_set or 'default')
      end
   end

   return entity
end

-- Returns the currently active model variant of the entity
-- if '' or 'default', tries to find a specific model variant with the active model file
function ace_client_entities.get_model_variant(entity, component_only)
   local render_info = entity and entity:get_component('render_info')
   if render_info then
      local model_variant = render_info:get_model_variant()
      if model_variant == '' or model_variant == 'default' then
         local model_variants = entity:get_component('model_variants')
         if model_variants then
            local models = {}
            local default_models = model_variants:get_variant('default')
            if default_models then
               for model in default_models:each_model() do
                  models[model] = true
               end

               -- now check each other variant to see if the same models are present
               local variant_from_comp, variant_from_json
               for id, variant in model_variants:each_variant() do
                  if id ~= 'default' then
                     if radiant.entities._model_variants_match(variant, models) then
                        variant_from_comp = id
                        break
                     end
                  end
               end

               if not component_only then
                  -- also check the component data in case this entity was created before the separate model variants were added
                  -- (model_variants component doesn't appear to get refreshed on reload, it's loaded separately as part of entity creation)
                  local json = radiant.entities.get_component_data(entity, 'model_variants')
                  if json then
                     for id, variant_data in pairs(json) do
                        if id ~= 'default' then
                           if radiant.entities._model_variants_from_json_match(variant_data, models) then
                              variant_from_json = id
                              break
                           end
                        end
                     end
                  end
               end

               return variant_from_json or variant_from_comp
            end
         end
      end
      return model_variant
   end
end

function ace_client_entities._model_variants_match(variant, models)
   local variant_models = {}
   for model in variant:each_model() do
      if not models[model] then
         return false
      end
      variant_models[model] = true
   end
   for model, _ in pairs(models) do
      if not variant_models[model] then
         return false
      end
   end

   return true
end

function ace_client_entities._model_variants_from_json_match(variant, models)
   local variant_models = {}
   for _, model in ipairs(variant.models) do
      if not models[model] then
         return false
      end
      variant_models[model] = true
   end
   for model, _ in pairs(models) do
      if not variant_models[model] then
         return false
      end
   end

   return true
end

function ace_client_entities.get_facing(entity)
   if not entity or not entity:is_valid() then
      return nil
   end

   local mob = entity:get_component('mob')
   if not mob then
      return nil
   end

   local rotation = mob:get_rotation()
   if rotation.x ~= 0 or rotation.z ~= 0 then
      -- if it's rotated on x or z, mob:get_facing() will cause a c++ assert fail!
      -- so get the flat y rotation instead
      rotation.x = 0
      rotation.z = 0
      rotation:normalize()
      -- angle in radians = 2 * acos(q.w); multiply by 180 / pi to convert to degrees
      return 360 * math.acos(rotation.w) / math.pi
   else
      return mob:get_facing()
   end
end

-- Returns the (voxel, integer) grid location in front of the specified entity.
function ace_client_entities.get_grid_in_front(entity)
   local mob = entity:get_component('mob')
   local facing = radiant.math.round(radiant.entities.get_facing(entity) / 90) * 90
   local location = mob:get_world_grid_location()
   local offset = radiant.math.rotate_about_y_axis(-Point3.unit_z, facing):to_closest_int()
   return location + offset
end

function ace_client_entities.is_solid_location(location)
   local entities = radiant.terrain.get_entities_at_point(location)

   for _, entity in pairs(entities) do
      if radiant.entities.is_solid_entity(entity) then
         return true
      end
   end

   return false
end

return ace_client_entities
