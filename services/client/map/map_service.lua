--[[
   The map service facillitates rendering the map for clients as well as reporting contents of map layers.
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4
local RegionCollisionType = _radiant.om.RegionCollisionShape

local MapService = class()

local log = radiant.log.create_logger('map_service')

function MapService:initialize()
   self._catalog_data = {}
   _radiant.call('stonehearth:get_all_catalog_data')
      :done(function(response)
         self._catalog_data = response
      end)
end

function MapService:render_map_command(session, response)
   self:render_map('map')
end

-- takes ~11 seconds to render a full 768x768 map (and 0.5 seconds to save to file)
-- takes ~0.67 second to render only every 4th block in each dimension (and 0.03 seconds to save to file)
-- can we turn it into a binary data image?
-- render on load and monitor terrain changes (and entity changes) to update the map?
-- break it up into chunks and render it over time?
function MapService:render_map(file_name, ray_height)
   -- time this so we know it's not too much of a burden
   local start_time = _host:get_realtime()

   local result = {}
   local terrain = radiant.terrain.get_terrain_component()
   local bounds = terrain:get_bounds()
   ray_height = (ray_height or 30) + bounds.max.y

   -- scan every 4 blocks; nothing important is going to only be really small, and terrain gen and mining are in 4x4 chunks
   for x = bounds.min.x, bounds.max.x - 1, 4 do
      --log:debug('starting scanning x = %s', x)
      local row = {}
      for z = bounds.min.z, bounds.max.z - 1, 4 do
         local p = Point3(x, ray_height, z)
         local end_point, entity = self:_get_entity_at_location(p)
         local block_type
         if entity then
            block_type = self:_get_block_type(entity, end_point)
         end

         table.insert(row, block_type or 0)
      end
      table.insert(result, row)
   end

   local end_time = _host:get_realtime()
   log:debug('Total time to render world: %s', end_time - start_time)

   radiant.mods.write_object(file_name or 'map_output', {
      data = result,
      bounds = bounds,
   })

   log:debug('Total time to save output file: %s', _host:get_realtime() - end_time)
end

function MapService:_get_entity_at_location(location)
   local end_point = _physics:shoot_ray(location, Point3(location.x, 0, location.z), true, 0)

   local entities = radiant.terrain.get_entities_at_point(end_point)
   for _, entity in pairs(entities) do
      if entity:get_id() == radiant._root_entity_id then
         return end_point, entity
      end

      local rcs = entity:get_component('region_collision_shape')
      if rcs and rcs:get_region_collision_type() ~= RegionCollisionType.NONE then
         return end_point, entity
      end
   end

   return end_point, nil
end

function MapService:_get_block_type(entity, end_point)
   -- check if the entity right above this point is in water
   local entities = radiant.terrain.get_entities_at_point(end_point + Point3.unit_y)
   for id, e in pairs(entities) do
      if e:get_uri() == 'stonehearth:terrain:water' then
         return 1000
      end
   end

   -- check if this is terrain; this should be the most common case, so do it first
   if entity:get_id() == radiant._root_entity_id then
      return radiant.terrain.get_block_tag_at(end_point)
   end

   -- check if this entity is a building
   if entity:get_component('stonehearth:build2:structure') then
      return 1001
   end

   -- check if this entity is a tree
   local catalog_data = self._catalog_data[entity:get_uri()]
   if catalog_data and catalog_data.category == 'plants' then
      return 1002
   end

   -- otherwise, try to find the terrain below this entity and return that block type
   local terrain_point = radiant.terrain.get_point_on_terrain(end_point)
   return terrain_point and radiant.terrain.get_block_tag_at(terrain_point)
end

return MapService
