--[[
   can contain specific information about that specific entity/component instance
   gets updated by any components that care
   can specify component data for it to hide generic or all info for select components
]]

local ComponentInfoComponent = class()

function ComponentInfoComponent:initialize()
   self._sv.components = {}
end

function ComponentInfoComponent:set_component_detail(component, name, detail, i18n_data, force_visible)
   local comp_detail = self:_add_component_detail(component, name, force_visible)
   comp_detail.detail = detail
   comp_detail.i18n_data = i18n_data

   self.__saved_variables:mark_changed()
end

function ComponentInfoComponent:remove_component_detail(component, name)
   local comp = self._sv.components[component]
   if comp then
      if comp[name] then
         comp[name] = nil
         self.__saved_variables:mark_changed()
      end
   end
end

function ComponentInfoComponent:set_component_general_hidden(component, hidden)
   local comp = self:_add_component(component)
   comp.hide_general = hidden
end

function ComponentInfoComponent:set_component_detail_hidden(component, hidden)
   local comp = self:_add_component(component)
   comp.hide_specific = hidden
end

function ComponentInfoComponent:_add_component(component)
   local comp = self._sv.components[component]
   if not comp then
      comp = {}
      self._sv.components[component] = comp
   end
   return comp
end

function ComponentInfoComponent:_add_component_detail(component, name, force_visible)
   local comp = self:_add_component(component)
   local comp_detail = comp[name]
   if not comp_detail then
      comp_detail = {}
      comp[name] = comp_detail
   end

   if force_visible then
      comp.hide_specific = nil
   end
   return comp_detail
end

return ComponentInfoComponent