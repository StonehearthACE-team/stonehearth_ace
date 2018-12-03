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
   self._sv.prev_banner = nil
   self._sv.path_to_next_banner = {}
   self._sv.distance_to_next_banner = nil
   self.__saved_variables:mark_changed()
end

function PatrolBannerComponent:activate()
   self._sv.location = radiant.entities.get_world_location(self._entity)
   local mob = self._entity:add_component('mob')
   self._parent_trace = mob:trace_parent('patrol banner added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function(parent_entity)
         if parent_entity then
            --we were just added to the world
            self:_on_position_set()
         end
      end)
   self._location_trace = mob:trace_transform('patrol banner moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
         self:_on_position_set()
      end)
   self:_create_new_banner_listener()
end

function PatrolBannerComponent:_on_position_set()
   local loc = radiant.entities.get_world_location(self._entity)

   -- we don't want to recalculate when the rotation changes, only when the location changes   
   if loc ~= self._sv.location then
      self._sv.location = loc
      self:_recalc_path_to_next_banner()
   end
end

function PatrolBannerComponent:destroy()
   self:_destroy_listeners()
   self:_remove_from_chain()
end

function PatrolBannerComponent:_destroy_listeners()
   if self._parent_trace then
		self._parent_trace:destroy()
		self._parent_trace = nil
   end
   if self._location_trace then
		self._location_trace:destroy()
		self._location_trace = nil
   end
   self:_destroy_next_banner_listener()
end

function PatrolBannerComponent:_remove_from_chain()
   if self._sv.prev_banner and not self._sv.prev_banner:is_valid() then
      self._sv.prev_banner = nil
   end
   if self._sv.next_banner and not self._sv.next_banner:is_valid() then
      self._sv.next_banner = nil
   end

   if self._sv.prev_banner then
      self._sv.prev_banner:get_component('stonehearth_ace:patrol_banner'):set_next_banner(self._sv.next_banner)
   end
   if self._sv.next_banner then
      self._sv.next_banner:get_component('stonehearth_ace:patrol_banner'):set_prev_banner(self._sv.prev_banner)
   end
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

function PatrolBannerComponent:get_party()
   return self._sv.party_id
end

function PatrolBannerComponent:set_party(party_id)
   self._sv.party_id = party_id
   self._sv.path_color = self._path_colors[party_id]
   self._entity:add_component('render_info'):set_model_variant(self._models[party_id or 'default'])
   self.__saved_variables:mark_changed()
end

function PatrolBannerComponent:get_next_banner()
   return self._sv.next_banner
end

-- next banner is used for calculating a path connecting this banner to it
function PatrolBannerComponent:set_next_banner(banner)
   if not banner or banner:get_component('stonehearth_ace:patrol_banner') then
      if banner == self._entity then
         self._sv.next_banner = nil
      else
         self._sv.next_banner = banner
      end
      self:_create_new_banner_listener()
      self:_recalc_path_to_next_banner()
   end
end

function PatrolBannerComponent:get_prev_banner()
   return self._sv.prev_banner
end

-- since this banner is the previous banner's "next banner," the connecting path is already being calculated there
-- this reference is just to allow us to easily get all the connecting banners with a doubly-linked list instead of singly-linked
function PatrolBannerComponent:set_prev_banner(banner)
   if not banner or banner:get_component('stonehearth_ace:patrol_banner') then
      if banner == self._entity then
         self._sv.prev_banner = nil
      else
         self._sv.prev_banner = banner
      end
      self.__saved_variables:mark_changed()
   end
end

function PatrolBannerComponent:get_path_to_next_banner()
   return self._sv.path_to_next_banner
end

function PatrolBannerComponent:get_distance_to_next_banner()
   return self._sv.distance_to_next_banner
end

--[[
   Should this call the more demanding synchronous pathfinder function?
   Otherwise it probably needs to track whether it's currently pathfinding and then cancel if a new request happens
]]
function PatrolBannerComponent:_recalc_path_to_next_banner()
   self._sv.path_to_next_banner = {}
   self._sv.distance_to_next_banner = nil

   --log:debug('_recalc_path_to_next_banner %s', self._sv.next_banner or 'NIL')
   if self._sv.next_banner and self._sv.next_banner:is_valid() then
      local location = self._sv.location
      --log:debug('banner location: %s', location or 'NIL')
      if location then
         local pf = self._entity:add_component('stonehearth:pathfinder')
         pf:find_path_to_entity(location, self._sv.next_banner,
            function(path)
               local points = path:get_points()
               self._sv.path_to_next_banner = points
               self._sv.distance_to_next_banner = path:get_path_length()

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

   radiant.events.trigger(self._entity, 'stonehearth_ace:patrol_banner:sequence_changed', self._entity)
end

return PatrolBannerComponent
