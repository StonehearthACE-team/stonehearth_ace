--[[
Based on the debug_shapes/box component and renderer.
]]

local NameOverlayComponent = class()

function NameOverlayComponent:initialize()
   self._sv.name = nil

   self._name_type_index = 1
end

function NameOverlayComponent:activate()
   local json = radiant.entities.get_json(self) or {}
   self._sv.category = json.category or 'default'

   -- listen for unit_info and job changes to update the name/icon
   self._unit_info_changed_listener = radiant.events.listen(self._entity, 'stonehearth:unit_info:changed', self, self._on_unit_info_changed)
   self._job_changed_listener = radiant.events.listen(self._entity, 'stonehearth:job_changed', self, self._on_job_changed)

   self:_on_unit_info_changed()
   self:_on_job_changed()

   -- listen for player amenities changes to trigger a change?
end

function NameOverlayComponent:destroy()
   if self._unit_info_changed_listener then
      self._unit_info_changed_listener:destroy()
      self._unit_info_changed_listener = nil
   end
end

function NameOverlayComponent:_on_unit_info_changed()
   -- only do the name if it's an entity with ai
   if self._entity:get_component('stonehearth:ai') then
      self:set_name(self._entity:get_component('stonehearth:unit_info'):get_custom_name())
   end

   -- only do the icon if it's an entity with no job
   if not self._entity:get_component('stonehearth:unit_info') then
      -- if it's a workshop, use the corresponding job icon
      if self._entity:get_component('stonehearth:workshop') then
         self:set_icon(self._entity:get_component('stonehearth:workshop'):get_job_icon())
      else
         self:set_icon(self._entity:get_component('stonehearth:unit_info'):get_icon())
      end
   end
end

function NameOverlayComponent:_on_job_changed()
   self:set_icon(self._entity:get_component('stonehearth:job'):get_curr_job_icon())
end

function NameOverlayComponent:set_name(n)
   if self._sv.name ~= n then
      self._sv.name = n
      self:_mark_changed()
   end
end

function NameOverlayComponent:set_icon(i)
   if self._sv.icon ~= i then
      self._sv.icon = i
      self:_mark_changed()
   end
end

function NameOverlayComponent:_mark_changed()
   self.__saved_variables:mark_changed()
end

return NameOverlayComponent
