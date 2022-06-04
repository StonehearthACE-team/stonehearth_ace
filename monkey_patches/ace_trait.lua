local Trait = require 'stonehearth.components.traits.trait'
local AceTrait = class()

AceTrait._ace_old_create = Trait.create
function AceTrait:create(entity, uri, args)
   self._is_create = true
   self:_ace_old_create(entity, uri, args)
end

AceTrait._ace_old_post_activate = Trait.post_activate
function AceTrait:post_activate()
   self:_ace_old_post_activate()
   if self._is_create then
      radiant.events.trigger(self._sv._entity, 'stonehearth_ace:trait_added', {uri = self._sv.uri})
   end
end

AceTrait._ace_old_destroy = Trait.__user_destroy
function AceTrait:destroy()
   radiant.events.trigger(self._sv._entity, 'stonehearth_ace:trait_removed', {uri = self._sv.uri})
   self:_ace_old_destroy()
end

function AceTrait:_init_i18n_data()
   self:add_i18n_data('entity_display_name', radiant.entities.get_display_name(self._sv._entity))
   self:add_i18n_data('entity_custom_name', radiant.entities.get_custom_name(self._sv._entity))
   self:add_i18n_data('entity_custom_data', radiant.entities.get_custom_data(self._sv._entity))
end

function AceTrait:get_icon()
   return self._sv.icon
end

return AceTrait
