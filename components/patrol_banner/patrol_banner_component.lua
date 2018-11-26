local Point3 = _radiant.csg.Point3
local PatrolBannerComponent = class()

function PatrolBannerComponent:initialize()
   self._models = (radiant.entities.get_json(self) or {}).models or {}
   self._sv.next_banner = nil
   self._sv.path_to_next_banner = {}
end

function PatrolBannerComponent:activate()
   self._location_trace = self._entity:add_component('mob'):trace_transform('patrol banner moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
            self:_recalc_path_to_next_banner()
         end)
   self:_create_new_banner_listener()
end

function PatrolBannerComponent:destroy()
   self:_destroy_listeners()
end

function PatrolBannerComponent:_destroy_listeners()
   if self._location_trace then
		self._location_trace:destroy()
		self._location_trace = nil
   end
   self:_destroy_next_banner_listener()
end

function PatrolBannerComponent:_create_new_banner_listener()
   if self._sv.next_banner and self._sv.next_banner:is_valid() then
      self._next_banner_trace = self._sv.next_banner:add_component('mob'):trace_transform('next banner moved', _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function()
               self:_recalc_path_to_next_banner()
            end)
   end
end

function PatrolBannerComponent:_destroy_next_banner_listener()
   if self._next_banner_trace then
      self._next_banner_trace:destroy()
      self._next_banner_trace = nil
   end
end

function PatrolBannerComponent:set_next_banner(banner)
   self._sv.next_banner = banner
   self:_create_new_banner_listener()
   self:_recalc_path_to_next_banner()
end

--[[
   Should this call the more demanding synchronous pathfinder function?
   Otherwise it probably needs to track whether it's currently pathfinding and then cancel if a new request happens
]]
function PatrolBannerComponent:_recalc_path_to_next_banner()
   if self._sv.next_banner and self._sv.next_banner:is_valid() then
      -- this isn't going to be called very frequently, so don't bother caching locations
      local location = radiant.terrain.get_world_location(self._entity)
      local target_location = radiant.terrain.get_world_location(self._sv.next_banner)
      if location and target_location then
         local pf = self._entity:add_component('stonehearth:pathfinder')
         pf:find_path_to_entity(location, target_location,
            function(path)
               self._sv.path_to_next_banner = path:get_path_points()
               self.__saved_variables:mark_changed()
            end,
            function()
               self._sv.path_to_next_banner = {}
               self.__saved_variables:mark_changed()
            end)
         return
      end
   end

   self._sv.path_to_next_banner = {}
   self.__saved_variables:mark_changed()
end

return PatrolBannerComponent
