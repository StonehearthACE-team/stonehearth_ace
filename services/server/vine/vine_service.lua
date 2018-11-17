--[[
   vines need to be able to grow when they're alone as well as when they're connected in graphs
]]
local log = radiant.log.create_logger('vine_service')

local VineService = class()

function VineService:initialize()
   self._networks_by_entity = {}
   local json = radiant.resources.load_json('stonehearth_ace:data:vine_types')
   self._vine_types = json.types or {}

   self._sv = self.__saved_variables:get_data()

   if not self._sv.controllers then
      self._sv.controllers = {}
   end
   
   self:_update_controllers()
end

function VineService:destroy()
end

function VineService:get_growth_data(uri)
   return self._vine_types[uri]
end

function VineService:_update_controllers()
   for type, type_data in pairs(self._vine_types) do
      if not self._sv.controllers[type] then
         self._sv.controllers[type] = radiant.create_controller('stonehearth_ace:vine', type, type_data)
         self.__saved_variables:mark_changed()
      end
   end
end

return VineService
