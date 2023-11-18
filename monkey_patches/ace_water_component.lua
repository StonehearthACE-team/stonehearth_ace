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
   self:_create_region_trace()
   
   -- movement modifier shape was a performance failure; remove it in case someone saved their game with it
   self._entity:remove_component('movement_modifier_shape')
end

AceWaterComponent._ace_old_activate = WaterComponent.activate
function AceWaterComponent:activate()
   self:_ace_old_activate()

   --self:_update_pathing()
   self:reset_changed_since_signal()
end

AceWaterComponent._ace_old_destroy = WaterComponent.__user_destroy
function AceWaterComponent:destroy()
   self:_destroy_region_trace()
   self:_ace_old_destroy()
   stonehearth_ace.water_signal:water_component_modified(self._entity)
end

function AceWaterComponent:_destroy_region_trace()
   if self._region_trace then
      self._region_trace:destroy()
      self._region_trace = nil
   end
end

-- trace the region so whenever it changes we can check again if it borders the world's edge
function AceWaterComponent:_create_region_trace()
   self:_destroy_region_trace()
   self._region_trace = self._sv.region:trace('water world edge check', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
         --self:_update_movement_modifier_shape()
         self:_check_if_at_world_edge()   
      end)
   
   --self:_update_movement_modifier_shape()
   self:_check_if_at_world_edge()
end

function AceWaterComponent:_check_if_at_world_edge()
   if not self._sv.region or not self._location then
      return
   end

   -- if it doesn't actually have any water in it yet, don't limit it that way
   -- only start limiting it once some water has been added
   if self._sv.height < constants.hydrology.MIN_INFINITE_WATER_HEIGHT then
      self._is_infinite = false
      return
   end

   local ring = self._world_edge_region
   if not ring then
      local bounds = radiant.terrain.get_terrain_component():get_bounds()
      -- get just the outside x/z ring
      ring = Region3()
      ring:add_cube(bounds:get_face(Point3.unit_x))
      ring:add_cube(bounds:get_face(-Point3.unit_x))
      ring:add_cube(bounds:get_face(Point3.unit_z))
      ring:add_cube(bounds:get_face(-Point3.unit_z))
      self._world_edge_region = ring
   end

   self._is_infinite = ring:translated(-self._location):intersects_region(self._sv.region:get())
   log:debug('%s checking if at world edge... %s', self._entity, self._is_infinite and 'YES' or 'NO')
end

function AceWaterComponent:reset_changed_since_signal()
   self._prev_level_since_signal = self._location and self:get_water_level()
end

function AceWaterComponent:was_changed_since_signal()
   return not self._prev_level_since_signal or not self._location or math.abs(self:get_water_level() - self._prev_level_since_signal) > 0.0001
end

function AceWaterComponent:_reset_changed_on_tick()
   self._prev_height = self._sv.height
   self._prev_region = Region3(self._sv.region:get())
   self._prev_location = self._location
   self._region_changed = nil
end

function AceWaterComponent:_was_changed_on_tick()
   if self._region_changed or
      self._prev_height ~= self._sv.height or
      self._prev_location ~= self._location then
      -- not csg_lib.are_same_shape_regions(self._prev_region, self._sv.region:get()) then
         log:debug('%s was changed on tick', self._entity)
         return true
   end

   return false
end

function AceWaterComponent:check_changed(override_check)
   if override_check or self:_was_changed_on_tick() then
      self:_reset_changed_on_tick()
      self._calculated_up_to_date = false
      stonehearth_ace.water_signal:water_component_modified(self._entity, true)
      self.__saved_variables:mark_changed()
   end
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

AceWaterComponent._ace_old_set_region = WaterComponent.set_region
function AceWaterComponent:set_region(boxed_region, height)
   self:_ace_old_set_region(boxed_region, height)
   self:_create_region_trace()

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)
   self:_update_destination()
   --self:_update_pathing()
end

-- ACE: have to override a bunch of functions to remove their saved_variables:mark_changed()

function AceWaterComponent:_add_height(volume)
   if volume == 0 then
      return 0
   end
   assert(volume > 0)

   if self._is_infinite then
      return 0
   end

   local top_layer = self._sv._top_layer:get()
   local layer_area = top_layer:get_area()
   assert(layer_area > 0)

   local delta = volume / layer_area
   local residual = 0
   local upper_limit = self._sv._top_layer_index + 1

   self._sv.height = self._sv.height + delta

   -- important that this is >= and not > because layer bounds are inclusive on min height but exclusive on max height
   if self._sv.height >= upper_limit then
      residual = (self._sv.height - upper_limit) * layer_area
      self._sv.height = upper_limit
      self:_raise_layer()
   end

   --self.__saved_variables:mark_changed()
   
   return residual
end

function AceWaterComponent:_raise_layer()
   local entity_location = self._location
   local new_layer_index = self._sv._top_layer_index + 1
   log:debug('Raising layer for %s to %d', self._entity, new_layer_index + entity_location.y)

   local top_layer = self._sv._top_layer:get()

   if top_layer:empty() then
      log:warning('Cannot raise layer for %s', self._entity)
      return false
   end

   assert(top_layer:get_rect(0).min.y + 1 == new_layer_index)

   -- convert to world space and raise one level
   local raised_layer = top_layer:translated(entity_location + Point3.unit_y)

   -- subtract any new obstructions
   local intersection = stonehearth.hydrology:get_water_tight_region():intersect_region(raised_layer)
   raised_layer:subtract_region(intersection)

   -- make sure we don't overlap any other water bodies
   self:_subtract_all_water_regions(raised_layer)

   raised_layer:optimize('water:_raise_layer() (raised layer)')

   -- back to local space
   raised_layer:translate(-entity_location)

   self._sv.region:modify(function(cursor)
         cursor:add_region(raised_layer)
         cursor:optimize('water:_raise_layer() (updating region)')
      end)

   self._sv._top_layer:modify(function(cursor)
         cursor:copy_region(raised_layer)
      end)
   self._sv._top_layer_index = new_layer_index

   self:_update_wetting_layer()

   --self.__saved_variables:mark_changed()
   self._region_changed = true

   self:_update_destination()

   return true
end

function AceWaterComponent:_remove_from_wetting_layer(num_blocks)
   local changed = false
   while num_blocks > 0 do
      local wetting_layer = self._sv._wetting_layer:get()
      if wetting_layer:empty() then
         break
      end

      local centroid = self._sv._top_layer:get():get_centroid()
      if not centroid then
         break
      end

      local point = wetting_layer:get_furthest_point(centroid)

      -- this call will update self._sv._wetting_layer
      self:_remove_point_from_region(point)
      num_blocks = num_blocks - 1
      changed = true
   end

   self:_update_destination()
   --self.__saved_variables:mark_changed()

   if changed then
      self._region_changed = true
      stonehearth_ace.water_signal:water_component_modified(self._entity)
   end

   return num_blocks
end

function AceWaterComponent:_remove_height(volume)
   if volume == 0 then
      return 0
   end
   assert(volume > 0)

   if self._is_infinite then
      return 0
   end

   local lower_limit = self._sv._top_layer_index   
   if self._sv.height <= lower_limit then
      self:_lower_layer()
      lower_limit = self._sv._top_layer_index
   end
   local residual = 0
   local top_layer = self._sv._top_layer:get()
   local layer_area = top_layer:get_area()

   if layer_area == 0 then
      return volume
   end

   local delta = volume / layer_area

   self._sv.height = self._sv.height - delta

   if self._sv.height < lower_limit then
      residual = (lower_limit - self._sv.height) * layer_area
      self._sv.height = lower_limit
   end

   --self.__saved_variables:mark_changed()
   return residual
end

function AceWaterComponent:_lower_layer()
   if not self:can_lower_layer() then
      return false
   end

   local channel_manager = stonehearth.hydrology:get_channel_manager()
   local entity_location = self._location

   -- make a copy so that this doesn't change when we change the region
   local top_layer = Region3(self._sv._top_layer:get())

   if not top_layer:empty() then
      assert(top_layer:get_rect(0).min.y == self._sv._top_layer_index)
   end

   local orphaned_wetting_regions = csg_lib.get_contiguous_regions(self._sv._wetting_layer:get())
   self:_create_orphaned_water_bodies(orphaned_wetting_regions)

   self:_remove_from_region(top_layer, { force_top_layer_changed = true })

   --self.__saved_variables:mark_changed()
   self._region_changed = true

   return true
end

function AceWaterComponent:_mark_water_added()
   self._sv._last_added_time = stonehearth.calendar:get_elapsed_time()
   --self.__saved_variables:mark_changed()
end

function AceWaterComponent:evaporate(amount)
   self._sv._last_evaporation_time = stonehearth.calendar:get_elapsed_time()

   if not self:top_layer_in_wetting_mode() then
      return amount
   end

   return self:_remove_from_wetting_layer(amount or 1)

   --self.__saved_variables:mark_changed()
end

-- written as a stateless function
-- mergee should be destroyed soon after this call
function WaterComponent:_merge_regions(master, mergee, allow_uneven_top_layers)
   assert(master ~= mergee)
   local master_component = master:add_component('stonehearth:water')
   local mergee_component = mergee:add_component('stonehearth:water')

   local master_location = master_component:get_location()
   local mergee_location = mergee_component:get_location()
   log:debug('Merging %s at %s with %s at %s', master, master_location, mergee, mergee_location)

   local master_layer_elevation = master_component:get_top_layer_elevation()
   local mergee_layer_elevation = mergee_component:get_top_layer_elevation()

   if master_layer_elevation ~= mergee_layer_elevation then
      master_component:_normalize()
      mergee_component:_normalize()
      master_layer_elevation = master_component:get_top_layer_elevation()
      mergee_layer_elevation = mergee_component:get_top_layer_elevation()
   end

   local translation = mergee_location - master_location   -- translate between local coordinate systems
   local update_layer, new_height, new_index, new_layer_region

   local is_uneven_merge = master_layer_elevation ~= mergee_layer_elevation
   local do_uneven_merge = allow_uneven_top_layers and is_uneven_merge

   if do_uneven_merge then
      if mergee_layer_elevation > master_layer_elevation then
         -- adopt the water level of the mergee
         update_layer = true
         new_height = mergee_component:get_water_level() - master_location.y
         new_index = mergee_layer_elevation - master_location.y

         -- clear the master layer since it will be replaced by the mergee layer below
         master_component._sv._top_layer:modify(function(cursor)
               cursor:clear()
            end)
      elseif mergee_layer_elevation < master_layer_elevation then
         -- we're good, just keep the existing layer as it is
         update_layer = false
      else
         assert(false)
      end
   else
      -- layers must be at same level
      assert(master_layer_elevation == mergee_layer_elevation)

      update_layer = true

      -- calculate new water level before modifying regions
      local new_water_level = self:_calculate_merged_water_level(master_component, mergee_component)
      new_height = new_water_level - master_location.y
      new_index = master_layer_elevation - master_location.y
   end

   -- merge the top layers
   if update_layer then
      master_component._sv.height = new_height
      master_component._sv._top_layer_index = new_index

      master_component._sv._top_layer:modify(function(cursor)
            local mergee_layer = mergee_component._sv._top_layer:get():translated(translation)
            cursor:add_region(mergee_layer)
            cursor:optimize('water:_merge_regions() (top_layer)')
         end)

      self:_update_wetting_layer()
   end

   -- merge the main regions
   master_component._sv.region:modify(function(cursor)
         local mergee_region = mergee_component._sv.region:get():translated(translation)
         cursor:add_region(mergee_region)
         cursor:optimize('water:_merge_regions() (region)')
      end)

   if translation.y < 0 then
      master_component:_move_to_new_origin()
   end

   if stonehearth.hydrology.enable_paranoid_assertions then
      master_component:_validate_top_layer(message)
   end

   --master_component.__saved_variables:mark_changed()
   master_component._region_changed = true
end

-- region must exist within the current y bounds of the existing water region
-- region in local coordinates
function AceWaterComponent:add_to_region(region)
   self._sv.region:modify(function(cursor)
         cursor:add_region(region)
         cursor:optimize('water:add_to_region()')
      end)

   local bounds = region:get_bounds()
   local max_index = bounds.max.y - 1 -- -1 to convert the upper bound to index space

   -- prohibit adding water above the top layer
   assert(max_index <= self._sv._top_layer_index)

   -- if we modified the top layer or the layer below it, recalculate it
   -- do this test before moving to new origin, because the rebasing code will change the top layer index
   -- -1 on the right to trigger on the layer just below the top layer
   if max_index >= self._sv._top_layer_index - 1 then
      self:_recalculate_top_layer()
   end

   -- if adding below the bottom layer, rebase the origin to the new floor
   if bounds.min.y < 0 then
      self:_move_to_new_origin()
   end

   --self.__saved_variables:mark_changed()
   self._region_changed = true
end

-- region in local coordinates
function AceWaterComponent:_add_to_top_layer(region)
   if region:empty() then
      return
   end

   self._sv.region:modify(function(cursor)
         cursor:add_region(region)
         cursor:optimize('water_component:_add_to_top_layer() (region)')
      end)

   self._sv._top_layer:modify(function(cursor)
         cursor:add_region(region)
         cursor:optimize('water_component:_add_to_top_layer() (top layer)')
      end)

   self:_update_wetting_layer()
   self:_update_destination()

   --self.__saved_variables:mark_changed()
   self._region_changed = true
end

-- region is in local coordinates
-- This may cause the location of the entity to change and the regions to translate if the origin is removed!
function AceWaterComponent:_remove_from_region_impl(region_to_remove, destroy_orphaned_channels, force_top_layer_changed)
   if region_to_remove:empty() and not force_top_layer_changed then
      return
   end

   local channel_manager = stonehearth.hydrology:get_channel_manager()

   if stonehearth.hydrology.enable_paranoid_assertions then
      channel_manager:check_all_channels()
   end

   self._sv.region:modify(function(cursor)
         cursor:subtract_region(region_to_remove)
         cursor:optimize('water_component:_remove_from_region_impl() (region)')
      end)

   local top_layer_changed = force_top_layer_changed or self._sv._top_layer:get():intersects_region(region_to_remove)

   if top_layer_changed then
      self._sv._top_layer:modify(function(cursor)
            cursor:subtract_region(region_to_remove)
            cursor:optimize('water_component:_remove_from_region_impl() (top_layer)')

            if cursor:empty() and self._sv._top_layer_index > 0 then
               -- reindex and get the new top layer
               self._sv._top_layer_index = self._sv._top_layer_index - 1
               local lowered_layer = self:_get_layer(self._sv._top_layer_index)
               cursor:copy_region(lowered_layer)
            end
         end)
   end

   self:_update_wetting_layer()

   if top_layer_changed then
      self:_update_destination()
   end

   if region_to_remove:contains(Point3.zero) then
      self:_move_to_new_origin()
   end

   if destroy_orphaned_channels then
      local region_to_remove_world = region_to_remove:translated(self._location)
      channel_manager:update_channels_on_region_removed(region_to_remove_world, self._entity)
   end

   --self.__saved_variables:mark_changed()
   self._region_changed = true
end

function AceWaterComponent:_move_to_new_origin()
   local region = self._sv.region:get()
   if region:empty() then
      return
   end

   -- Region is in local coordinates of the old_origin so the new origin returned is also in the
   -- old coordinate system.
   local delta = stonehearth.hydrology:select_origin_for_region(region)
   local old_origin = self._location
   local new_origin = old_origin + delta
   -- offset is actually just -delta, but be explicit for clarity
   -- (to world coordinates then back to local coordinates in the new coordiante system)
   local offset = old_origin - new_origin

   log:debug('Moving %s from %s to %s', self._entity, old_origin, new_origin)

   self._sv.region:modify(function(cursor)
         cursor:translate(offset)
      end)
   assert(self._sv.region:get():get_bounds().min.y == 0)

   self._sv._top_layer:modify(function(cursor)
         cursor:translate(offset)
      end)
   assert(self._sv._top_layer:get():get_bounds().min.y >= 0)

   self._sv._wetting_layer:modify(function(cursor)
         cursor:translate(offset)
      end)
   assert(self._sv._wetting_layer:get():get_bounds().min.y >= 0)

   if offset.y ~= 0 then
      self._sv.height = self._sv.height + offset.y
      self._sv._top_layer_index = self._sv._top_layer_index + offset.y
   end

   radiant.terrain.place_entity_at_exact_location(self._entity, new_origin)

   -- update the cached location
   self._location = new_origin

   self:_update_destination()
   self:_check_if_at_world_edge()

   --self.__saved_variables:mark_changed()
end

function AceWaterComponent:_update_wetting_layer()
   local wetting_layer = self:_calculate_wetting_layer()
   -- Keep this assertion so that we don't end up with a water body in an inconsistent state.
   -- We must place the water body before setting it's region so that we can
   -- calculate a wetting layer for it.
   assert(wetting_layer, 'cannot calculate wetting layer when we are not in the world')

   self._sv._wetting_layer:modify(function(cursor)
         cursor:copy_region(wetting_layer)
      end)

   --self.__saved_variables:mark_changed()
end

function AceWaterComponent:_recalculate_top_layer()
   local layer = self:_get_layer(self._sv._top_layer_index)

   self._sv._top_layer:modify(function(cursor)
         cursor:copy_region(layer)
      end)

   self:_update_wetting_layer()
   self:_update_destination()

   --self.__saved_variables:mark_changed()
end

function AceWaterComponent:_update_destination()
   local destination = self._sv._top_layer:get():extruded('y', 0, 1)
   local destination_component = self._entity:add_component('destination')
   destination_component:set_auto_update_adjacent(true)
   destination_component:get_region():modify(function(cursor)
         cursor:copy_region(destination)
      end)
end

function AceWaterComponent:_update_movement_modifier_shape()
   local mms = self._entity:add_component('movement_modifier_shape')
   if not mms:get_region() then
      mms:set_region(_radiant.sim.alloc_region3())
      mms:set_nav_preference_modifier(-0.5)
   end
   mms:get_region():modify(function(cursor)
         cursor:copy_region(self._sv.region:get())
         cursor:optimize_by_defragmentation('water movement modifier shape')
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
   --self.__saved_variables:mark_changed()
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
