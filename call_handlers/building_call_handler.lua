local Region3 = _radiant.csg.Region3
local validator = radiant.validator
local BuildingCallHandler = class()

-- client function
function BuildingCallHandler:dump_selected_building(session, response)
   -- get the selected building from the client build service and pass that along to the server function
   local id = stonehearth.building:get_current_building_id()
   local building = radiant.entities.get_entity(id)
   if building then
      _radiant.call('stonehearth_ace:dump_building_server', building)
         :done(function(result)
            response:resolve(result)
         end)
         :fail(function(result)
            response:reject(result)
         end)
   else
      response:reject('no currently selected building')
   end
end

-- server function
function BuildingCallHandler:dump_building_server(session, response, building)
   validator.expect_argument_types({'Entity'}, building)

   local total_building_region = self:_dump_building_to_region(building)

   if total_building_region then
      local name = radiant.entities.get_custom_name(building)
      if not name or name == '' then
         name = 'building'
      end

      name = name .. '.qb'
      _radiant.sim.dump_region(total_building_region, name)
      response:resolve({file_name = name})
   else
      response:reject('Error: could not get colored region for selected building (may need to click Build and unpause first)')
   end
end

function BuildingCallHandler:_dump_building_to_region(building)
   local build_comp = building:get('stonehearth:build2:building')
   if build_comp and build_comp:get_building_status() >= stonehearth.constants.building.building_status.BUILDING then
      local region = Region3()
      for _, structure in pairs(build_comp:get_all_structures()) do
         local structure_comp = structure:get('stonehearth:build2:structure')
         if structure_comp then
            local origin = structure_comp:get_origin()
            local cr = structure_comp:get_desired_color_region():translated(origin)

            for cube in cr:each_cube() do
               region:add_cube(cube)
            end
         end
      end

      return region
   end
end

function BuildingCallHandler:get_roof_tool_options(session, response)
   response:resolve(stonehearth.building:get_roof_tool_options())
end

function BuildingCallHandler:set_roof_tool_options(session, response, options)
   stonehearth.building:set_roof_tool_options(options)
   return true
end

return BuildingCallHandler
