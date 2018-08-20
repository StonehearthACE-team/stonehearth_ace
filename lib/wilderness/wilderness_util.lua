local wilderness = {}
local log = radiant.log.create_logger('wilderness_heatmap')
-- we allow an optional catalog lookup function to be passed in so this can be used from the client as well

local get_block_kind_at = radiant.terrain.get_block_kind_at

function wilderness.default_catalog_fn(uri)
   return stonehearth.catalog:get_catalog_data(uri)
end

function wilderness.get_value_from_entity(entity, catalog_fn, sampling_region)
   local value = 0
   local region = nil
   local component = entity:get_component('stonehearth_ace:wilderness')
   
   -- if the component exists, why doesn't the function sometimes?
   if component and component.get_wilderness_value then
      value = component:get_wilderness_value()
   else
      component = entity:get_component('stonehearth:build2:structure')
      if component then
         -- if it's a building, it counts as negative wilderness value
         region = wilderness._get_region(entity)
         if region then
            value = -2 * region:get_area()
         else
            value = -10
         end
      else
         -- if it's a 'plant', use its collision region area as its value
         -- if it's an animal... uh... say 5?
         catalog_fn = catalog_fn or wilderness.default_catalog_fn
         local catalog_data = catalog_fn(entity:get_uri())
         if catalog_data then
            if catalog_data.player_id == 'animals' then
               value = 5
            elseif catalog_data.category == 'plants' then
               region = wilderness._get_region(entity)
               if region then
                  value = region:get_area()
               else
                  value = 1
               end
            end
         end
      end
   end

   -- make the value proportional to how much of the entity is within the sampling cube, if specified
   if sampling_region and value ~= 0 then
      region = region or wilderness._get_region(entity)
      if region then
         local intersection = region:intersect_region(sampling_region)
         if intersection:empty() then
            value = 0
         else
            value = value * intersection:get_area() / region:get_area()
         end
      end
   end

   return value
end

function wilderness._get_region(entity)
   local component = entity:get_component('region_collision_shape') or entity:get_component('destination')
   if component then
      local location = radiant.entities.get_world_location(entity)
      if location then
         return component:get_region():get():translated(location)
      end
   end
   return nil
end

function wilderness.has_wilderness_value(entity, catalog_fn)
   local component = entity:get_component('stonehearth_ace:wilderness') or entity:get_component('stonehearth:build2:structure')
   if component then
      return true
   else
      -- we don't care about ghost or iconic entities: only regular entities can contribute to wilderness value
      -- so we don't need to involve entity_forms
      catalog_fn = catalog_fn or wilderness.default_catalog_fn
      local catalog_data = catalog_fn(entity:get_uri())
      return catalog_data and (catalog_data.player_id == 'animals' or catalog_data.category == 'plants')
   end
end

function wilderness.get_value_from_terrain(location)
   local kind = get_block_kind_at(location)
   if kind == 'grass' then
      return 0.02
   elseif kind == 'dirt' then
      return 0.01
   else
      return 0
   end
end

return wilderness