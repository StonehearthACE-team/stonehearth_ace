local AceScaffoldingRegion = class()

local log = radiant.log.create_logger('build.scaffolding.region')

-- ACE BUILD HEIGHT: change self._sv._current_height_w calculations to better minimize scaffolding construction

function AceScaffoldingRegion:set_data(building_chunk_entity, final_region)
   self._sv._building_chunk_origin = radiant.entities.get_world_grid_location(building_chunk_entity)
   self._sv._origin = radiant.entities.get_world_grid_location(self._entity)
   self._sv._final_region = final_region
   self._sv._building_chunk_entity = building_chunk_entity
   self._building_chunk_c = self._sv._building_chunk_entity:get_component('stonehearth:build2:chunk')

   self._sv._build_height = self._building_chunk_c:get_build_height()

   self._entity:get_component('region_collision_shape'):get_region():modify(function(cursor)
         cursor:copy_region(final_region)
      end)

   local bounds = self._building_chunk_c:get_remaining():get_bounds()
   local min_y = math.max(bounds.min.y - 1, bounds.max.y - self._sv._build_height)
   self._sv._current_height_w = min_y + self._sv._building_chunk_origin.y
end

function AceScaffoldingRegion:_on_chunk_dst_updated()
   if self._sv._final_region:get_area() == self._chunk_c:get_completed():get_area() then
      log:info('done.')
      radiant.events.trigger_async(self._entity, 'stonehearth:build2:scaffolding_region_done', self._entity:get_id())
   end

   if self._building_chunk_c:get_remaining():get_bounds():get_area() == 0 then
      return
   end

   -- We don't adjust the scaffolding desired region until the remaining building region is out of our
   -- reach.
   local remaining_min_y = self._building_chunk_c:get_remaining():get_bounds().min.y + self._sv._building_chunk_origin.y
   if remaining_min_y <= self._sv._current_height_w + self._sv._build_height then
      return
   end

   local remaining_max_y = self._building_chunk_c:get_remaining():get_bounds().max.y + self._sv._building_chunk_origin.y

   if remaining_max_y - remaining_min_y > self._sv._build_height then
      self._sv._current_height_w = remaining_min_y
   else
      self._sv._current_height_w = remaining_max_y - self._sv._build_height
   end
   self:_update_desired_region()
end

return AceScaffoldingRegion
