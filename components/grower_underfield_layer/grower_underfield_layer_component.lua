local GrowerUnderfieldLayerComponent = class()

local VERSIONS = {
   ZERO = 0,
   ADD_OWNER_ID = 1
}

function GrowerUnderfieldLayerComponent:get_version()
   return VERSIONS.ADD_OWNER_ID
end

function GrowerUnderfieldLayerComponent:initialize()
   self._sv.grower_underfield = nil
end

function GrowerUnderfieldLayerComponent:fixup_post_load(old_save_data)
   if old_save_data.version < VERSIONS.ADD_OWNER_ID then
      if self._entity:get_player_id() == '' then
         radiant.entities.set_player_id(self._entity, 'player_1')
      end
   end
end

function GrowerUnderfieldLayerComponent:set_grower_underfield(underfield)
   self._sv.grower_underfield = underfield
   self.__saved_variables:mark_changed()
end

function GrowerUnderfieldLayerComponent:get_grower_underfield()
   return self._sv.grower_underfield
end

return GrowerUnderfieldLayerComponent
