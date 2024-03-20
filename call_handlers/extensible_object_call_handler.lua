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

   local can_contain_uris = {}
   local can_contain_entity_filter = nil

   if component_data.accept_water ~= false then
      can_contain_uris['stonehearth:terrain:water'] = true
      can_contain_uris['stonehearth:terrain:waterfall'] = true
   end

   if next(can_contain_uris) then
      can_contain_entity_filter = function(entity, selector)
         log:debug('checking contain entity filter on %s (%s)', entity, tostring(can_contain_uris[entity:get_uri()]))
         return can_contain_uris[entity:get_uri()]
      end
   end

   local selector = stonehearth.selection:select_xyz_range('extensible_object_range_selector')
      :set_relative_entity(entity)
      :set_rotations(rotations)
      :set_multi_select_enabled(component_data.multi_select_enabled or false)
      :require_unblocked(component_data.require_unblocked or true)
      :set_can_pass_through_terrain(component_data.can_pass_through_terrain or true)
      :set_can_pass_through_buildings(component_data.can_pass_through_buildings or true)
      :set_ignore_middle_collision(component_data.ignore_middle_collision or false)  -- may need to set this to true if weird behavior colliding with terrain/buildings
      :set_can_contain_entity_filter(can_contain_entity_filter)

   if component_data.cursor then
      selector:set_cursor(component_data.cursor)
   end

   if component_data.multi_select_enabled then
      local ext_obj_data = entity:get_component('stonehearth_ace:extensible_object'):get_data()
      for i = 1, #rotations do
         if ext_obj_data.cur_extensions[rotations[i].connector_id] then
            selector:set_rotation_in_use(i, true)
         end
      end

      selector:progress(
         function(sel, is_notify_resolve, rotation_index, length, region, output_point)
            -- we only care about the user clicking, not moving the mouse
            if is_notify_resolve and rotation_index then
               local output_origin = length and sel:get_point_in_current_direction(length - 1)
               _radiant.call('stonehearth_ace:set_extensible_object_command', entity, rotation_index, length, region, sel:get_current_connector_region(), output_point, output_origin)
                  :always(
                     function()
                        if rotation_index then
                           sel:set_rotation_in_use(rotation_index, length ~= nil)
                        end
                     end
                  )
            end
         end
      )
   else
      selector:done(
         function(sel, rotation_index, length, region, output_point)
            local output_origin = length and sel:get_point_in_current_direction(length - 1)
            _radiant.call('stonehearth_ace:set_extensible_object_command', entity, rotation_index, length, region, sel:get_current_connector_region(), output_point, output_origin)
               :done(
                  function(r)
                     response:resolve({})
                  end
               )
               :always(
                  function()
                     sel:destroy()
                  end
               )
         end
      )
   end

   selector:fail(
         function(sel)
            sel:destroy()
            response:reject('no region')
         end
      )
      :go()
end

function ExtensibleObjectCallHandler:set_extensible_object_command(session, response, entity, rotation_index, length, region_table, connector_region_table, output_point, output_origin)
   -- apparently Region3 parameters get turned into tables and have to be loaded
   validator.expect_argument_types({'Entity', 'number', validator.optional('number'), validator.optional('table'), validator.optional('table'), validator.optional('Point3'), validator.optional('Point3')},
         entity, rotation_index, length, region_table, connector_region_table, output_point, output_origin)

   local region, connector_region

   if region_table then
      region = Region3()
      region:load(region_table)
   end

   if connector_region_table then
      connector_region = Region3()
      connector_region:load(connector_region_table)
   end

   local extensible_object_comp = entity:get_component('stonehearth_ace:extensible_object')
   if extensible_object_comp then
      extensible_object_comp:set_extension(rotation_index, length, region, connector_region, radiant.util.to_point3(output_point), radiant.util.to_point3(output_origin))
   end

   response:resolve({})
end

function ExtensibleObjectCallHandler:remove_extensible_object_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local extensible_object_comp = entity:get_component('stonehearth_ace:extensible_object')
   if extensible_object_comp then
      extensible_object_comp:set_extension(nil)
   end

   response:resolve({})
end

return ExtensibleObjectCallHandler
