local RegionCollisionType = _radiant.om.RegionCollisionShape
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local validator = radiant.validator

local MechanicalCallHandler = class()

local log = radiant.log.create_logger('mechanical_call_handler')

function MechanicalCallHandler:select_gearbox_axles_command(session, response, gearbox)
   validator.expect_argument_types({'Entity'}, gearbox)

   local rotations = radiant.util.get_rotations_table(radiant.entities.get_component_data(gearbox, 'stonehearth_ace:gearbox'))
   if #rotations < 1 then
      response:reject({})
      return
   end

   local selector = stonehearth.selection:select_xyz_range('gearbox_axles_range_selector')
      --:set_cursor('stonehearth:cursors:fence')
      :set_relative_entity(gearbox)
      :set_rotations(rotations)
      :set_multi_select_enabled(true)
      :progress(
         function(selector, is_notify_resolve, rotation_index, length, region, output_point)
            -- we only care about the user clicking, not moving the mouse
            if is_notify_resolve and rotation_index then
               log:debug('stonehearth_ace:set_gearbox_axle_command(%s, %s, %s, ...)', gearbox, rotation_index, length)
               log:debug('rotations in use: %s', radiant.util.table_tostring(selector._rotations_in_use))
               _radiant.call('stonehearth_ace:set_gearbox_axle_command', gearbox, rotation_index, length, selector:get_current_connector_region(), region)
                  :always(
                     function()
                        if rotation_index then
                           selector:set_rotation_in_use(rotation_index, length > 0)
                        end
                     end
                  )
            end
         end
      )
      :fail(
         function(selector)
            selector:destroy()
            response:resolve({})
         end
      )

   local gearbox_comp = gearbox:get_component('stonehearth_ace:gearbox')
   local cur_axles = gearbox_comp:get_data().cur_axles
   local axles_in_use = {}
   for i = 1, #rotations do
      if cur_axles[rotations[i].connector_id] then
         selector:set_rotation_in_use(i, true)
      end
   end

   selector:go()
end

function MechanicalCallHandler:set_gearbox_axle_command(session, response, gearbox, rotation_index, length, connector_region_table, collision_region_table)
   -- apparently Region3 parameters get turned into tables and have to be loaded
   validator.expect_argument_types({'Entity', 'number', 'number', 'table', validator.optional('table')},
                                    gearbox, rotation_index, length, connector_region_table, collision_region_table)

   local connector_region = Region3()
   connector_region:load(connector_region_table)

   local collision_region
   if collision_region_table then
      collision_region = Region3()
      collision_region:load(collision_region_table)
   end

   local gearbox_comp = gearbox:get_component('stonehearth_ace:gearbox')

   if gearbox_comp then
      gearbox_comp:set_axle_extension(rotation_index, length, connector_region, collision_region)
   end

   response:resolve({})
end

function MechanicalCallHandler:reset_gearbox_axles_command(session, response, gearbox)
   validator.expect_argument_types({'Entity'}, gearbox)

   local gearbox_comp = gearbox:get_component('stonehearth_ace:gearbox')

   if gearbox_comp then
      gearbox_comp:set_axle_extension(nil)
   end

   response:resolve({})
end

return MechanicalCallHandler
