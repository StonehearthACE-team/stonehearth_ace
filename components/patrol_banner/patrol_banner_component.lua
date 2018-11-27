local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('patrol_banner_component')

local PatrolBannerComponent = class()

function PatrolBannerComponent:initialize()
   local json = radiant.entities.get_json(self) or {}
   self._models = json.models or {}
   self._path_colors = json.path_colors or {}
   self._sv.party_id = 'party_1'
   self._sv.path_color = self._path_colors[self._sv.party_id]
   self._sv.next_banner = nil
   self._sv.path_to_next_banner = {}
   self.__saved_variables:mark_changed()
end

function PatrolBannerComponent:activate()
   self._sv.location = radiant.entities.get_world_location(self._entity)
   self._location_trace = self._entity:add_component('mob'):trace_transform('patrol banner moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
         -- we don't want to recalculate when the rotation changes, only when the location changes   
         local loc = radiant.entities.get_world_location(self._entity)
         if loc ~= self._sv.location then
            self._sv.location = loc
            self:_recalc_path_to_next_banner()
         end
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
   self:_destroy_next_banner_listener()
   if self._sv.next_banner and self._sv.next_banner:is_valid() then
      self._sv.next_location = radiant.entities.get_world_location(self._sv.next_banner)
      self._next_banner_trace = self._sv.next_banner:add_component('mob'):trace_transform('next banner moved', _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function()
               -- we don't want to recalculate when the rotation changes, only when the location changes   
               local loc = radiant.entities.get_world_location(self._sv.next_banner)
               if loc ~= self._sv.next_location then
                  self._sv.next_location = loc
                  self:_recalc_path_to_next_banner()
               end
            end)
   else
      self._sv.next_location = nil
   end
end

function PatrolBannerComponent:_destroy_next_banner_listener()
   if self._next_banner_trace then
      self._next_banner_trace:destroy()
      self._next_banner_trace = nil
   end
end

function PatrolBannerComponent:set_party(party_id)
   self._sv.party_id = party_id
   self._sv.path_color = self._path_colors[party_id]
   self._entity:add_component('render_info'):set_model_variant(self._models[party_id])
   self.__saved_variables:mark_changed()
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
   self._sv.path_to_next_banner = {}

   if self._sv.next_banner and self._sv.next_banner:is_valid() then
      -- this isn't going to be called very frequently, so don't bother caching locations
      local location = self._sv.location
      if location then
         local pf = self._entity:add_component('stonehearth:pathfinder')
         pf:find_path_to_entity(location, self._sv.next_banner,
            function(path)
               --log:debug('path to next banner: %s', radiant.util.table_tostring(path:get_points()))
               local points = path:get_points()
               self._sv.path_to_next_banner = points
               local mob = self._entity:add_component('mob')
               mob:turn_to_face_point(#points > 2 and points[3] or 0)
               mob:turn_to(mob:get_facing() - 90)
               self.__saved_variables:mark_changed()
            end,
            function()
               self.__saved_variables:mark_changed()
            end)
         return
      end
   end

   self.__saved_variables:mark_changed()
end

return PatrolBannerComponent
