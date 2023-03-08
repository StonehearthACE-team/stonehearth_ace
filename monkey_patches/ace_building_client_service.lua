local Point3 = _radiant.csg.Point3

local AceBuildingClientService = class()

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

return AceBuildingClientService
