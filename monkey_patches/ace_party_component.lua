local Point3 = _radiant.csg.Point3

local PartyComponent = radiant.mods.require('stonehearth.components.party.party_component')
local AcePartyComponent = class()

AcePartyComponent._old__initialize_party = PartyComponent._initialize_party
function AcePartyComponent:_initialize_party()
   self:_old__initialize_party()
   self:_update_manage_party_command()
end

function AcePartyComponent:_update_manage_party_command()
   local command_component = self._entity:add_component('stonehearth:commands')
   command_component:add_command('stonehearth_ace:commands:manage_parties')
   command_component:set_command_event_data('stonehearth_ace:commands:manage_parties', {party = self._sv.banner_variant})
end

AcePartyComponent._old_set_banner_variant = PartyComponent.set_banner_variant
function AcePartyComponent:set_banner_variant(variant)
   self:_old_set_banner_variant(variant)
   self:_update_manage_party_command()
end

return AcePartyComponent
