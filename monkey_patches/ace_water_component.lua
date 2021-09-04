local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local constants = require 'stonehearth.constants'

local log = radiant.log.create_logger('water')

local WaterComponent = require 'stonehearth.components.water.water_component'
local AceWaterComponent = class()

AceWaterComponent._ace_old_restore = WaterComponent.restore
function AceWaterComponent:restore()
   self:_ace_old_restore()
   self:_update_destination()
end

AceWaterComponent._ace_old_activate = WaterComponent.activate
function AceWaterComponent:activate()
   self:_ace_old_activate()

   --self:_update_pathing()
   self:reset_changed_on_tick()
end

function AceWaterComponent:reset_changed_on_tick()
   self._prev_level = self._location and self:get_water_level()
end

function AceWaterComponent:was_changed_on_tick()
   return not self._prev_level or not self._location or math.abs(self:get_water_level() - self._prev_level) > 0.0001
end

function AceWaterComponent:get_volume_info()
   if not self._calculated_up_to_date then
      local location = self._location
      local top_region = self._sv._top_layer:get():translated(location)
      local top_height = self._sv.height % 1
      local base_region = self._sv.region:get():translated(location) - top_region
      self._calculated_volume_info = {
         base_region = base_region,
         top_region = top_region,
         top_height = top_height
      }
      self._calculated_up_to_date = true
   end
   return self._calculated_volume_info
end

-- this is used instead of evaporate() so that it only triggers on actual evaporation
AceWaterComponent._ace_old__remove_from_wetting_layer = WaterComponent._remove_from_wetting_layer
function AceWaterComponent:_remove_from_wetting_layer(num_blocks)
   local value = self:_ace_old__remove_from_wetting_layer(num_blocks)

   if num_blocks > 0 then
      stonehearth_ace.water_signal:water_component_modified(self._entity)
   end

   return value
end

AceWaterComponent._ace_old_add_water = WaterComponent.add_water
function AceWaterComponent:add_water(volume, add_location)
   local volume, info = self:_ace_old_add_water(volume, add_location)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity, true)

   return volume, info
end

AceWaterComponent._ace_old_remove_water = WaterComponent.remove_water
function AceWaterComponent:remove_water(volume, clamp)
   local volume = self:_ace_old_remove_water(volume, clamp)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity, true)

   return volume
end

AceWaterComponent._ace_old_merge_with = WaterComponent.merge_with
function AceWaterComponent:merge_with(mergee, allow_uneven_top_layers)
   self:_ace_old_merge_with(mergee, allow_uneven_top_layers)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)
   stonehearth_ace.water_signal:water_component_modified(mergee)
end

AceWaterComponent._ace_old_set_region = WaterComponent.set_region
function AceWaterComponent:set_region(boxed_region, height)
   self:_ace_old_set_region(boxed_region, height)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)
   self:_update_destination()
   --self:_update_pathing()
end

AceWaterComponent._ace_old__raise_layer = WaterComponent._raise_layer
function AceWaterComponent:_raise_layer()
   local result = self:_ace_old__raise_layer()
   if result then
      self:_update_destination()
   end
end

function AceWaterComponent:_update_destination()
   local destination = self._sv._top_layer:get():extruded('y', 0, 1)
   local destination_component = self._entity:add_component('destination')
   destination_component:set_auto_update_adjacent(true)
   destination_component:get_region():modify(function(cursor)
         cursor:copy_region(destination)
      end)
end

-- function AceWaterComponent:_update_pathing()
--    -- if we want to enable vertical pathing in water regions, this is where we do that (or queue it)
--    -- updates to large/complex water bodies can potentially cause lag
--    -- entities tend to walk on water for a bit before getting low enough to trigger their swimming animation
--    stonehearth_ace.water_signal:water_component_pathing_modified(self._entity)
-- end

-- function AceWaterComponent:update_pathable_region()
--    if self._sv.region and (not self._sv.last_updated_pathable_region or not self._sv.last_updated_pathable_region:equals(self._sv.region:get())) then
--       -- only add it to the horizontal layer of water that's one voxel down from the top
--       local region = self._sv.region:get():extruded('y', 0, -1)
--       local bounds = region:get_bounds()
--       region:subtract_region(Region3(bounds):extruded('y', 0, -1))

--       region:optimize('water pathing')
--       self._entity:add_component('stonehearth_ace:vertical_pathing_region'):set_region(region)
--       self._sv.last_updated_pathable_region = self._sv.region:get()
--       self.__saved_variables:mark_changed()
--    end
-- end

-- ACE: have to override these functions to fix the max y of world bounds
-- For performance we manually, update the edge and channel regions in this method.
-- All parameters are in world coordinates
function AceWaterComponent:_grow_region(volume, add_location, top_layer, edge_region, channel_region)
   local channel_manager = stonehearth.hydrology:get_channel_manager()
   local world_bounds = radiant.terrain.get_terrain_component():get_bounds()
   world_bounds.max.y = constants.terrain.MAX_Y_OVERRIDE
   local entity_location = self._location
   local top_layer = Region3(top_layer) -- consider removing this copy
   local add_region = Region3()
   local info = {}

   -- grow the region until we run out of volume or edges
   while volume > 0 and not edge_region:empty() do
      if volume < constants.hydrology.WETTING_VOLUME * 0.5 then
         -- too little volume to wet a block, so just let it evaporate
         volume = 0
         break
      end

      local point = edge_region:get_closest_rectangular_point(add_location)
      local target_entity = stonehearth.hydrology:get_water_body_at(point)
      if target_entity == self._entity then
         -- The top layer is likely missing points and growing the edge region over the water region.
         -- If this occurs, flag the bug so we can fix it, but continue the simulation by recalculating the top layer.
         self:_validate_top_layer('grow_region')
         self:_recalculate_top_layer()
         break
      end

      edge_region:subtract_point(point)

      if target_entity then
         local target_water_component = target_entity:add_component('stonehearth:water')
         local target_height = target_water_component:get_water_level()
         if target_height == self:get_water_level() then
            -- request merge before adding more water
            info = {
               result = 'merge',
               entity = target_entity
            }
            break
         else
            -- create a pressure channel
            local to_point = point
            local from_point = top_layer:get_closest_point(to_point)
            assert(from_point.y == to_point.y)
            assert((to_point - from_point):length_squared() == 1)
            channel_manager:add_pressure_channel_bidirectional(from_point, to_point, self._entity, target_entity)
            channel_region:add_point(to_point)
         end
      elseif self:_is_blocked(point - Point3.unit_y) then
          -- make this location wet
          if not self:_is_blocked(point) then
            log:debug('Wetting %s for %s', point, self._entity)
            add_region:add_point(point)
            top_layer:add_point(point)

            for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
               -- for performance, we manually modify the edge region
               local adjacent_point = point + direction
               if world_bounds:contains(adjacent_point) then
                  if not self:_is_blocked(adjacent_point) and not top_layer:contains(adjacent_point) and not channel_region:contains(adjacent_point) then
                     edge_region:add_point(adjacent_point)
                  end
               end
            end
            volume = self:_subtract_wetting_volume(volume)
         end
      else
         -- create a waterfall channel
         local from_point = top_layer:get_closest_point(point)
         local direction = point - from_point
         assert(direction:length_squared() == 1)
         local channel = channel_manager:add_waterfall_channel(from_point, point, self._entity, nil)
         channel_region:add_point(point)
         local removal = volume > 1 and 1 or volume --TODO:add to constants
         channel_manager:add_water_to_waterfall(channel, removal)
         volume = volume - removal
      end
   end

   add_region:optimize('water:_grow_region')
   add_region:translate(-entity_location)
   self:_add_to_top_layer(add_region)
   self:_update_wetting_layer()
   self.__saved_variables:mark_changed()
   return volume, info
end

-- return value and parameters all in world coordinates
function AceWaterComponent:_get_edge_region(region, channel_region)
   local world_bounds = self._terrain_component:get_bounds()
   world_bounds.max.y = stonehearth.constants.terrain.MAX_Y_OVERRIDE

   -- perform a separable inflation to exclude diagonals
   -- TODO: consider using csg::GetAdjacent here
   local edge_region = region:inflated(Point3.unit_x)
   edge_region:add_region(region:inflated(Point3.unit_z))

   -- subtract the interior region
   edge_region:subtract_region(region)

   -- remove watertight region
   stonehearth.hydrology:get_water_tight_region():subtract_from(edge_region)

   -- remove channels that we've already processed
   if channel_region then
      edge_region:subtract_region(channel_region)
   end

   -- remove locations outside the world
   edge_region = edge_region:intersect_cube(world_bounds)

   edge_region:optimize('water:_get_edge_region()')
 
   return edge_region
end

return AceWaterComponent
