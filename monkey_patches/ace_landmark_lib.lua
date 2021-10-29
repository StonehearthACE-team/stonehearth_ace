local Region3 = _radiant.csg.Region3
local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local LandmarkLib = require 'stonehearth.lib.landmark.landmark_lib'
local terrain_blocks = radiant.resources.load_json("stonehearth:terrain_blocks", true, false)

local MATERIAL_TAG_DEFAULT = terrain_blocks.block_types.dirt.tag
local MATERIAL_TAG_NULL = terrain_blocks.block_types.null.tag

local DEBUG_LANDMARK = radiant.util.get_global_config('mods.stonehearth.landmark.create_debug_mesh', false)
local DEBUG_LANDMARK_OFFSET = radiant.util.get_global_config('mods.stonehearth.landmark.debug_mesh_offset', 50)

local AceLandmarkLib = {}

-- ACE: have to copy this whole thing just to have it properly override existing water with air when appropriate
-- options = {
--    brush                            - The mesh specifying the terrain to generate.
--    brush_mask                       - This is a duplicate mesh that the user repaints with colors of materials they want to spawn when mined.  string of json file location.
--    translation                      - Manual offset from the bottom center of the .qb file.  { "x": 1, "y": 1, "z": 1 },
--    rotation                         - Desired facing of the object (which offsets from the 'facing' entry on the landmark_blocks).  single value for rotation in y-axis.
--    scale                            - Value of scale to multiply the .qb file.  Can be a single number, or table of { "x": 1, "y": 1, "z": 1 }.
--    destroy_entity_search_volume     - Value of inflation on region to destroy entities in the world.  Can be a single number, or table of { "x": 1, "y": 1, "z": 1 }.
--    tag                              - Default tag to use if a tag isn't recognized.  hex number for color.
--    is_mimic                         - Bool which tells all voxels of qb mesh to override and become the tag under the spawn of the location given.  boolean.
--    override_tag                     - Override tag which replaces all tags of non-water or mimic with this tag color.  hex number for color.
--    destroy_entities                 - Bool to determine if all entities are destroyed within or slightly above the brush's region.  boolean.
--    destroy_hearthlings              - Same as above, but applies to hearthlings.  boolean.
--    clip_if_outside_terrain          - This bool determines if the operation being done is outside the bounds of the terrain, and clips it to stay within if found.  boolean.
--    fill_voxel_with_water            - This bool forces the voxel where the entity is placed to fill with water.  boolean.
--    landmark_block_types             - This is a table which contains all information needed to place the desired qb asset as a landmark and later mine that region.  uri of landmark blocks table.
-- }
function AceLandmarkLib.create_qb_as_terrain(location, options)
   assert(location, "Location not provided to LandmarkComponent")
   assert(options.brush, "QB Brush not provided to LandmarkComponent")
   
   -- Make sure we randomize location once for both the main brush and the mask.
   options = radiant.shallow_copy(options)
   if options.rotation == 'random' then
      options.rotation = rng:get_int(0, 3) * 90
   end

   local water_bucket = {}
   local water_bucket_lowered = {}
   local region = LandmarkLib.get_generated_landmark_region(location, options)
   local brush_mask
   local region_mask = Region3()
   local region_mask_removal = Region3()
   -- Gather the mask qb file if available, and ensure that the brush_mask is of the same region as the main brush
   if options.brush_mask then
      brush_mask = _radiant.voxel.create_qubicle_brush(options.brush_mask)
      region_mask = brush_mask:paint_once():translated(location)
   else
      local brush = _radiant.voxel.create_qubicle_brush(options.brush)
      region_mask = brush:paint_once():translated(location)
   end
   local translation = options.translation or {x=0,y=0,z=0}
   local rotation = options.rotation or 0
   local scale = options.scale or {x=1,y=1,z=1}
   if type(scale) == "number" then
      scale = {x=scale,y=scale,z=scale}
   end
   local destroy_entity_search_volume = options.destroy_entity_search_volume or {x=0,y=1,z=0}
   if type(destroy_entity_search_volume) == "number" then
      destroy_entity_search_volume = {x=destroy_entity_search_volume, y=destroy_entity_search_volume, z=destroy_entity_search_volume}
   end
   local tag = options.tag and terrain_blocks.block_types[options.tag].tag or MATERIAL_TAG_DEFAULT
   local is_mimic = options.is_mimic
   local mimic_tag = LandmarkLib.find_tag_on_terrain(location) or MATERIAL_TAG_DEFAULT
   local override_tag = options.override_tag
   local destroy_entities = options.destroy_entities
   local destroy_hearthlings = options.destroy_hearthlings
   local clip_if_outside_terrain = options.clip_if_outside_terrain or true
   local landmark_block_types = radiant.resources.load_json(options.landmark_block_types, true, false)
   
   region_mask = LandmarkLib._transform_region(region_mask, location, translation, rotation, scale)
   if clip_if_outside_terrain then
      region_mask = LandmarkLib.intersect_with_terrain_bounds_and_remove_bedrock(region_mask)
   end
   region_mask = region_mask:intersect_region(region)
   local remove_water_region = Region3()

   -- TODO: Do better clean up of waterbodies when placing on top of one.
   if destroy_entities then
      LandmarkLib._destroy_entities(region, destroy_entity_search_volume, destroy_hearthlings)
   end
   if is_mimic then
      for cube in region:each_cube() do
         cube.tag = tag
         radiant.terrain.add_cube(cube)
      end
   else
      -- ACE: is there a better way? pre-processing to remove water rather than allow terrain change triggers
      for cube in region:each_cube() do
         cube = cube:to_int()

         local hex_color = LandmarkLib.convert_decimal_to_hexadecimal(cube.tag)
         local terrain_tag = LandmarkLib.get_tag_from_color(hex_color, landmark_block_types)

         if terrain_tag then
            remove_water_region:add_cube(cube)
         else
            local block_properties = landmark_block_types[hex_color]
            if block_properties and block_properties.fill_voxel_with_water == false then
               -- ACE: specifically if it's false, make sure water is removed from this region
               remove_water_region:add_cube(cube)
            end
         end
      end

      if not remove_water_region:empty() then
         AceLandmarkLib._remove_water_region(remove_water_region)
      end

      for cube in region:each_cube() do
         -- Need to ensure that all cubes are in the right place after all the adjustments above, so we floor them.
         cube = cube:to_int()

         local hex_color = LandmarkLib.convert_decimal_to_hexadecimal(cube.tag)
         local terrain_tag = LandmarkLib.get_tag_from_color(hex_color, landmark_block_types)
         local block_properties = landmark_block_types[hex_color]

         if terrain_tag then
            cube.tag = terrain_tag
            if cube.tag == MATERIAL_TAG_NULL then
               radiant.terrain.subtract_cube(cube)
               region_mask:subtract_cube(cube)
            else
               radiant.terrain.add_cube(cube)
            end
         else
            -- If it is a specific color we want to mess with, then claim that here and remove terrain from that location.  Else, go on to entity blocks.
            if hex_color == landmark_block_types.color_water then
               table.insert(water_bucket, cube)
               radiant.terrain.subtract_cube(cube)
               region_mask:subtract_cube(cube)
            elseif hex_color == landmark_block_types.color_water_lowered then
               table.insert(water_bucket_lowered, cube)
               radiant.terrain.subtract_cube(cube)
               region_mask:subtract_cube(cube)
            elseif hex_color == landmark_block_types.color_mimic_tag then
               cube.tag = mimic_tag
               radiant.terrain.add_cube(cube)
               region_mask:subtract_cube(cube)

            -- If specific color is not found, set to either specified or default value.
            -- Check if it is a color representing an entity in the list which is passed in, if so: delete the cube and place the entity.
            -- TODO: Maybe some entities (if users specifies) could attach and face away from the normal of the surface they are being placed on (like wall decorations).
            else
               if block_properties then
                  local items = LandmarkLib.convert_uri_or_lootbag_to_loottable(block_properties.loot_bag)
                  local entity = nil
                  if block_properties.placement_chance then
                     items = LandmarkLib._apply_loot_chance(items, block_properties.placement_chance) or {}
                  end
                  -- If items exists, create only the first one.
                  -- TODO: Print a warning if more than one is rolled.
                  local item = next(items)
                  if item then
                     entity = radiant.entities.create_entity(item, {owner = block_properties.owner})
                     if entity then
                        radiant.terrain.place_entity_at_exact_location(entity, Point3(cube.min.x, cube.min.y, cube.min.z), {force_iconic = block_properties.force_iconic or false})
                     end
                  end
                  if block_properties.facing ~= nil and entity then
                     local final_facing
                     if block_properties.facing == "random" then
                        final_facing = rng:get_int(0,3)*90
                     else
                        final_facing = math.floor(block_properties.facing + rotation) % 360
                     end
                     entity:add_component('mob'):turn_to(final_facing)
                  end
                  -- And make sure to remove the cube from the terrain (not the region) so we don't have terrain on top of our placed entity.
                  radiant.terrain.subtract_cube(cube)
                  region_mask:subtract_cube(cube)
                  if block_properties.fill_voxel_with_water then
                     table.insert(water_bucket, cube)
                  elseif block_properties.fill_voxel_with_low_water then
                     table.insert(water_bucket_lowered, cube)
                  end
               else
                  -- If not a terrain color and not an entity color, then it is just a color.  Add it to terrain as that color.
                  -- If there is no mask, then adjust the mask we have made by setting it to the default (or desired) tag.
                  radiant.terrain.add_cube(cube)
                  if not options.brush_mask then
                     cube.tag = tag
                     region_mask:add_cube(cube)
                  end
               end
            end
         end
      end

      -- Need to merge all water cubes, then separate them: csg.lib get contiguous regions (returns list), then create those water volumes.
      if next(water_bucket) then
         AceLandmarkLib._create_water_regions(water_bucket, 0)
      end
      if next(water_bucket_lowered) then
         AceLandmarkLib._create_water_regions(water_bucket_lowered, 0.5)
      end
   end

   -- After we are all set with the qb brushes we are inserting, need to add our mask mesh to the terrain landmark table.
   -- If there is an override_tag, then use it to replace the tag of all mask cubes
   if override_tag then
      region_mask = Region3()
      local desired_tag = LandmarkLib.convert_hexadecimal_to_decimal(override_tag)
      for cube in region:each_cube() do
         cube.tag = desired_tag
         region_mask:add_cube(cube)
      end
   end
   radiant.terrain.add_landmark(region_mask, landmark_block_types)

   -- When toggled, this will place the region_mask as a terrain object offset in the world
   if DEBUG_LANDMARK then
      region_mask = region_mask:translated(Point3(DEBUG_LANDMARK_OFFSET,0,0))
      radiant.terrain.add_region(region_mask)
   end
end

-- ACE: don't clip max y to the hard-coded 256 in the terrain component
-- Remove any part of region that is outside the allowed bounds of terrain or intersects with bedrock (tag of 100)
function AceLandmarkLib.intersect_with_terrain_bounds_and_remove_bedrock(region)
   -- Remove out of bounds areas
   local bounds = radiant.terrain.get_terrain_component():get_bounds()
   bounds.max.y = stonehearth.constants.terrain.MAX_Y_OVERRIDE
   region = region:intersect_cube(bounds)
   -- Remove bedrock areas
   local terrain_check_region = radiant.terrain.intersect_cube(region:get_bounds())
   for cube in terrain_check_region:each_cube() do
      if cube.tag and cube.tag == terrain_blocks.block_types.bedrock.tag then
         region:subtract_cube(cube)
      end
   end
   return region
end

-- Take a list of water regions, merge them together to a single region, split them into continguous regions, then create them.
function AceLandmarkLib._create_water_regions(water_regions, water_offset)
   local contiguous_regions = {}
   local all_water_region = Region3()
   for _, cube in pairs(water_regions) do
      all_water_region:add_cube(cube)
   end
   contiguous_regions = csg_lib.get_contiguous_regions(all_water_region)
   for _, region in pairs(contiguous_regions) do
      local bounds = region:get_bounds()
      local height = bounds.max.y - bounds.min.y - water_offset
      stonehearth.hydrology:create_water_body_with_region(region, height, true)  -- ACE: true to merge with adjacent water regions
   end
end

function AceLandmarkLib._remove_water_region(region)
   local water_entities = radiant.terrain.get_entities_in_region(region,
      function(entity)
         return entity:get_uri() == 'stonehearth:terrain:water'
      end)

   for id, water_entity in pairs(water_entities) do
      local water_component = water_entity:add_component('stonehearth:water')
      water_component:remove_from_region(region)
      water_component:check_changed(true)
   end
end

return AceLandmarkLib
