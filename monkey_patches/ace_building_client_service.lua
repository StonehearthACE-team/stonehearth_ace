local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local build_util = require 'stonehearth.lib.build_util'

local BuildingClientService = require 'stonehearth.services.client.building.building_client_service'
local AceBuildingClientService = class()

local log = radiant.log.create_logger('building_service')

AceBuildingClientService._ace_old_on_server_ready = BuildingClientService.on_server_ready
function AceBuildingClientService:on_server_ready()
   self:_ace_old_on_server_ready()

   _radiant.call('stonehearth_ace:get_build_grid_offset')
      :done(function(r)
            self._build_grid_offset = radiant.util.to_point2(r.offset)
         end)
end

function AceBuildingClientService:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if mode == 'build' then
      _radiant.renderer.set_pipeline_stage_enabled('BuildingFilter', stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'enable_building_filter'))
      _radiant.renderer.set_pipeline_stage_enabled('Buildings', true)
      self:set_widgets_visible(true)
   else
      _radiant.renderer.set_pipeline_stage_enabled('BuildingFilter', false)
      _radiant.renderer.set_pipeline_stage_enabled('Buildings', false)
      self:set_widgets_visible(false)
   end
end

function AceBuildingClientService:destroy_building_command(session, response, restore_terrain)
   _radiant.call_obj(self._build_service, 'destroy_building_command', self._current_building_id, restore_terrain):done(function(res)
         self:_update_current_building(res.result)
      end)
end

function AceBuildingClientService:build(session, response, insert_craft_requests)
   self:_destroy_tool(true)
   self:_destroy_cursor()

   self._sv.selection:clear_selected()
   self.__saved_variables:mark_changed()

   _radiant.call_obj(self._build_service, 'build_command', self._current_building_id, Point3(0, 0, 0), insert_craft_requests)
      :done(function(r)
            response:resolve(r.result)
         end)
end

function AceBuildingClientService:get_build_grid_offset()
   return self._build_grid_offset or Point2.zero
end

function AceBuildingClientService:set_build_grid_offset(offset)
   self._build_grid_offset = offset
   _radiant.call('stonehearth_ace:set_build_grid_offset', offset)
end

function AceBuildingClientService:get_current_building_room_region()
   local region = Region3()
   local current_building = radiant.entities.get_entity(self:get_current_building_id())
   local building_comp = current_building and current_building:get_component('stonehearth:build2:building')
   if building_comp then
      -- go through all the blueprints; if they're rooms, add their region bounds to this region
      local regions = {}
      for _, bp in building_comp:get_blueprints():each() do
         if bp:get_uri() == 'stonehearth:build2:entities:room_blueprint' then
            local blueprint_comp = bp:get_component('stonehearth:build2:blueprint')
            local data = blueprint_comp:get_data()
            if data.origin and data.region then
               table.insert(regions, data.region:translated(data.origin))
            end
         end
      end

      region = build_util.calculate_building_terrain_cutout(regions)
   end

   log:debug('calculated current building room region: %s (bounds = %s)', region, region:get_bounds())
   return region
end

return AceBuildingClientService
