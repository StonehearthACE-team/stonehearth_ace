--[[
   this component allows an entity to act as a proxy owner for an ownable object
   for now, merely used to indicate a "type" of ownership (beds reserved for medic patients)
]]

local OwnerProxyComponent = class()

function OwnerProxyComponent:activate()
   self._json = radiant.entities.get_json(self) or {}

   if self._sv._reserved_entity then
      self:_make_ownership_listener()
   end
end

function OwnerProxyComponent:destroy()
   if self._ownership_listener then
      self._ownership_listener:destroy()
      self._ownership_listener = nil
   end
end

function OwnerProxyComponent:_make_ownership_listener()
   if self._ownership_listener then
      self._ownership_listener:destroy()
   end

   self._ownership_listener = radiant.events.listen(self._sv._reserved_entity, 'stonehearth:owner_changed', self, self._on_owner_changed)
end

function OwnerProxyComponent:_on_owner_changed(e)
   if not e.new_owner or e.new_owner ~= self._entity then
      radiant.entities.destroy_entity(self._entity)
   end
end

function OwnerProxyComponent:get_type()
   return self._sv.type or self._json.type or 'invalid'
end

-- allow for an override so separate entity jsons aren't required for every type
function OwnerProxyComponent:set_type(new_type)
   self._sv.type = new_type
   self.__saved_variables:mark_changed()
end

function OwnerProxyComponent:track_reservation(entity)
   self._sv._reserved_entity = entity
   self:_make_ownership_listener()
   entity:get_component('stonehearth:ownable_object'):set_owner(self._entity)
end

return OwnerProxyComponent
