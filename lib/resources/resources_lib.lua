local resources_lib = {}

-- also used by farmer_field component when toggling harvest_enabled status
function resources_lib.request_auto_harvest(entity, should_auto_harvest)
   local crop_comp = entity:get_component('stonehearth:crop')
   if should_auto_harvest or (crop_comp and crop_comp:get_field():is_harvest_enabled() and not entity:get_component('stonehearth:evolve')) then
      local renewable_resource_node = entity:get_component('stonehearth:renewable_resource_node')
      local resource_node = entity:get_component('stonehearth:resource_node')

      if renewable_resource_node and renewable_resource_node:is_harvestable() then
         return renewable_resource_node:request_harvest(entity:get_player_id())
      elseif resource_node and not crop_comp or not renewable_resource_node then
         return resource_node:request_harvest(entity:get_player_id())
      end
   end
end

function resources_lib.cancel_harvest_request(entity)
   local renewable_resource_node = entity:get_component('stonehearth:renewable_resource_node')
   local resource_node = entity:get_component('stonehearth:resource_node')

   if renewable_resource_node then
      renewable_resource_node:cancel_harvest_request()
   end
   if resource_node then
      resource_node:cancel_harvest_request()
   end
end

function resources_lib.is_harvest_requested(entity)
   local renewable_resource_node = entity:get_component('stonehearth:renewable_resource_node')
   local resource_node = entity:get_component('stonehearth:resource_node')

   return (renewable_resource_node and renewable_resource_node:is_harvest_requested()) or
         (resource_node and resource_node:is_harvest_requested())
end

function resources_lib.toggle_harvest_requests(entities, prefer_requested)
   -- first go through all the entities and determine which have harvest requests
   -- if prefer_requested isn't false, cancel all harvest requests only if all are requested; otherwise, request harvest on all that aren't already
   -- if prefer_requested is false, do the reverse: request harvest only if none are requested
   local harvesting = {}
   local not_harvesting = {}
   prefer_requested = prefer_requested ~= false

   for id, entity in pairs(entities) do
      if entity:is_valid() then
         if resources_lib.is_harvest_requested(entity) then
            table.insert(harvesting, entity)
         else
            table.insert(not_harvesting, entity)
         end
      end
   end

   if (prefer_requested and #not_harvesting > 0) or (not prefer_requested and #harvesting == 0) then
      for _, entity in ipairs(not_harvesting) do
         resources_lib.request_auto_harvest(entity, true)
      end
   else
      for _, entity in ipairs(harvesting) do
         resources_lib.cancel_harvest_request(entity, true)
      end
   end
end

return resources_lib
