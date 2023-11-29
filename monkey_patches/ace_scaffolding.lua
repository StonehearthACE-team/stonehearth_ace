local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local AceScaffolding = class()

local log = radiant.log.create_logger('scaffolding')

-- ACE: an event triggering this is async, and can cause an invalid entity reference
-- The scaffolding structure is home to multiple overlapping scaffolding regions.  It can be the case that two overlapping
-- regions come online at the same time, one on top of the other.  We need to ensure that the _bottom_-most scaffolding
-- is allowed to build completely first (and allow the chunk to finish!) before moving on to the upper one.  Hence,
-- a clip mask, applied to the structure, that chunks clip themselves against, in order to facilitate this.
function AceScaffolding:_compute_clip_mask()
   local origin = radiant.entities.get_world_grid_location(self._entity)
   local clip_mask = Region3()
   for c_id, chunks in pairs(self._sv._incomplete_chunks) do
      for _, s_id in ipairs(chunks) do
         local scaffolding_chunk = self._sv._scaffolding_chunks[s_id]
         if scaffolding_chunk then
            local chunk_origin = radiant.entities.get_world_grid_location(scaffolding_chunk)
            local final = scaffolding_chunk:get('stonehearth:build2:scaffolding_region'):get_final():translated(chunk_origin - origin)
            local final_bounds = final:get_bounds()
            -- We want to remove everything from the top of this region, to the height of the scaffolding.
            clip_mask:add_cube(Cube3(
                  Point3(final_bounds.min.x, final_bounds.max.y, final_bounds.min.z),
                  Point3(final_bounds.max.x, 999999, final_bounds.max.z)
               )
            )
            --log:debug('adding clip mask %s from incomplete chunk %s scaffolding chunk %s', clip_mask:get_bounds(), c_id, s_id)
         else
            log:debug('scaffolding chunk %s is missing from incomplete chunk %s!', s_id, c_id)
         end
      end
   end
   clip_mask:optimize('scaffolding clip mask')

   return clip_mask
end

return AceScaffolding
