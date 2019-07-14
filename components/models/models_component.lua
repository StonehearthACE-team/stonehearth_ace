--[[
   this component is used in conjunction with the models component renderer to render additional models for an entity
   for example, to easily add/remove berries to/from a berry bush when it ripens or is harvested
]]

local ModelsComponent = class()

function ModelsComponent:initialize()
   self._sv.models = {}
end

function ModelsComponent:add_model(name, options)
   self:set_model_options(name, options)
end

function ModelsComponent:remove_model(name)
   self._sv.models[name] = nil
   self.__saved_variables:mark_changed()
end

function ModelsComponent:set_model_options(name, options)
   local model = self._sv.models[name]
   options = radiant.shallow_copy(options)
   if options.visible == nil then
      options.visible = (not model or model.visible == nil) or model.visible
   end
   self._sv.models[name] = options
   self.__saved_variables:mark_changed()
end

function ModelsComponent:set_model_visibility(name, visible)
   local model = self._sv.models[name]
   if model then
      model.visible = visible
      self.__saved_variables:mark_changed()
   end
end

return ModelsComponent
