--[[
   an entity with this component serves as an access node to a universal storage entity
   when activated/destroyed, it needs to register/unregister with the universal_storage service
   the service will handle tracing placement in the world to adjust destination regions
   if it's destroyed as the last access node to a universal storage entity, the service will dump the universal storage's items
]]

local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local UniversalStorageComponent = class()

function UniversalStorageComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   self._sv.group_id = nil
end

function UniversalStorageComponent:activate()
   self:_register()
end

function UniversalStorageComponent:destroy()
   self:_unregister()
end

function UniversalStorageComponent:_register()
   stonehearth_ace.universal_storage:register_storage(self._entity)
end

function UniversalStorageComponent:_unregister()
   stonehearth_ace.universal_storage:unregister_storage(self._entity)
end

function UniversalStorageComponent:get_category()
   return self._json.category
end

function UniversalStorageComponent:get_group_id()
   return self._sv.group_id
end

-- this should only be called by the universal_storage service, which also handles re-registration when necessary
function UniversalStorageComponent:set_group_id(id)
   if id ~= self._sv.group_id then
      self._sv.group_id = id
      self.__saved_variables:mark_changed()
   end
end

return UniversalStorageComponent
