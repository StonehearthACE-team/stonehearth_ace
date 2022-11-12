local Point3 = _radiant.csg.Point3

local AceBuildingClientService = class()

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
