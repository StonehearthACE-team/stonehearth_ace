--[[
   can contain specific information about that specific entity/component instance
   gets updated by any components that care
   can specify component data for it to hide generic or all info for select components
]]

local ComponentInfoComponent = class()

function ComponentInfoComponent:initialize()
   self._sv.components = {}
   self._sv.force_update = 0
end

function ComponentInfoComponent:set_component_detail(component, name, detail, i18n_data, ordinal, force_visible)
   local comp_detail = self:_add_component_detail(component, name, ordinal, force_visible)
   if type(detail) == 'string' then
      detail = {
         type = 'string',
         content = detail
      }
   end
   comp_detail.detail = detail
   comp_detail.i18n_data = i18n_data or {}

   self.__saved_variables:mark_changed()
end

function ComponentInfoComponent:remove_component_detail(component, name)
   local comp = self._sv.components[component]
   if comp then
      if comp.details[name] then
         comp.details[name] = nil
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
      comp = {
         details = {}
      }
      self._sv.components[component] = comp
   end
   return comp
end

function ComponentInfoComponent:_add_component_detail(component, name, ordinal, force_visible)
   local comp = self:_add_component(component)
   local comp_detail = comp.details[name]
   
   if ordinal and comp_detail then
      comp_detail.ordinal = ordinal
   end
   if not comp_detail then
      if not ordinal then
         for _, detail in pairs(comp.details) do
            ordinal = math.min(detail.ordinal, ordinal or detail.ordinal)
         end
         ordinal = (ordinal or 0) + 1
      end
      comp_detail = {
         ordinal = ordinal
      }
      comp.details[name] = comp_detail
   end

   if force_visible then
      comp.hide_specific = nil
   end
   return comp_detail
end

-- hopefully force the ui to update traces
function ComponentInfoComponent:_force_update()
   self._sv.force_update = self._sv.force_update + 1
   self.__saved_variables:mark_changed()
end

return ComponentInfoComponent