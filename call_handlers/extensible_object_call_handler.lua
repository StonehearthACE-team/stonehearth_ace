local RegionCollisionType = _radiant.om.RegionCollisionShape
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local validator = radiant.validator

local ExtensibleObjectCallHandler = class()

local log = radiant.log.create_logger('extensible_object_call_handler')

function ExtensibleObjectCallHandler:select_extensible_object_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local component_data = radiant.entities.get_component_data(entity, 'stonehearth_ace:extensible_object')
   local rotations = radiant.util.get_rotations_table(component_data)
   if #rotations < 1 then
      response:reject({})
      return
   end

   if component_data.accept_water then
      local can_contain_uris = {
         ['stonehearth:terrain:water'] = true,
         ['stonehearth:terrain:waterfall'] = true,
      }
   end

   stonehearth.selection:select_xyz_range('extensible_object_range_selector')
      --:set_cursor('stonehearth:cursors:fence')
      :set_relative_entity(entity)
      :set_rotations(rotations)
      :set_multi_select_enabled(component_data.multi_select_enabled or false)
      :require_unblocked(component_data.require_unblocked or true)
      :set_can_pass_through_terrain(component_data.can_pass_through_terrain or true)
      :set_can_pass_through_buildings(component_data.can_pass_through_buildings or true)
      :set_ignore_middle_collision(component_data.ignore_middle_collision or false)  -- may need to set this to true if weird behavior colliding with terrain/buildings
      -- :set_can_contain_entity_filter(
      --    function(entity, selector)
      --       return can_contain_uris[entity:get_uri()]
      --    end
      -- )
      :done(
         function(selector, rotation_index, length, region, output_point)
            local output_origin = selector:get_point_in_current_direction(length - 1)
            _radiant.call('stonehearth_ace:set_extensible_object_command', entity, rotation_index, length, region, output_point, output_origin)
               :done(
                  function(r)
                     response:resolve({})
                  end
               )
               :always(
                  function()
                     selector:destroy()
                  end
               )
         end
      )
      :fail(
         function(selector)
            selector:destroy()
            response:reject('no region')
         end
      )
      :go()
end

function ExtensibleObjectCallHandler:set_extensible_object_command(session, response, entity, rotation_index, length, region_table, output_point, output_origin)
   -- apparently Region3 parameters get turned into tables and have to be loaded
   validator.expect_argument_types({'Entity', 'number', 'number', 'table', 'Point3', 'Point3'}, entity, rotation_index, length, region_table, output_point, output_origin)

   local region = Region3()
   region:load(region_table)

   local extensible_object_comp = entity:get_component('stonehearth_ace:extensible_object')
   local sponge_comp = entity:get_component('stonehearth_ace:water_sponge')

   if extensible_object_comp then
      extensible_object_comp:set_extension(rotation_index, length, region)
   end

   if sponge_comp then
      -- also apparently a Point3 isn't actually a Point3
      sponge_comp:set_output_location(radiant.util.to_point3(output_point), radiant.util.to_point3(output_origin))
   end

   response:resolve({})
end

function ExtensibleObjectCallHandler:remove_extensible_object_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local extensible_object_comp = entity:get_component('stonehearth_ace:extensible_object')
   local sponge_comp = entity:get_component('stonehearth_ace:water_sponge')

   if extensible_object_comp then
      extensible_object_comp:set_extension(nil)
   end

   if sponge_comp then
      sponge_comp:set_output_location(nil)
   end

   response:resolve({})
end

return ExtensibleObjectCallHandler
