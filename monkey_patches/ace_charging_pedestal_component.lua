local AmberstoneChargingPedestalComponent = require 'stonehearth.entities.gizmos.charging_pedestal.charging_pedestal_component'
local UnitInfoComponent = require 'stonehearth.components.unit_info.unit_info_component'

-- Accumulates charges over time while placed in the world, and emits
-- a "stonehearth:amberstone:pedestal_charged" event on the entity when
-- MAX_CHARGE is reached.
local AceAmberstoneChargingPedestalComponent = radiant.class()

local MAX_CHARGE = 70
local CHARGE_PER_HOUR = 2
local UNIT_INFO_LOCK_KEY = 'stonehearth:amberstone:pedestal_charger'

AceAmberstoneChargingPedestalComponent._ace_old_activate = AmberstoneChargingPedestalComponent.activate
function AceAmberstoneChargingPedestalComponent:activate()
   local json = radiant.entities.get_json(self) or {}
   self._max_charge = json.max_charge or MAX_CHARGE
   self._charge_per_hour = json.charge_per_hour or CHARGE_PER_HOUR
   self._charging_display_name = json.charging_display_name or 'i18n(stonehearth:entities.gizmos.charging_pedestal.charging_display_name)'

   local unit_info_json = radiant.entities.get_component_data(self._entity, 'stonehearth:unit_info')
   self._lock_key = unit_info_json and UnitInfoComponent.get_locked_key(unit_info_json) or UNIT_INFO_LOCK_KEY

   self:_ace_old_activate()
end

function AceAmberstoneChargingPedestalComponent:_charge()
   -- Make sure we are deployed.
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   -- TODO: Check that we aren't underground.

   -- Charge.  ACE: cap it at MAX_CHARGE
   self._sv.charge = math.min(self._max_charge, self._sv.charge + self._charge_per_hour)
   self.__saved_variables:mark_changed()
   
   -- Update name to indicate charging status.
   -- ACE: adjust to lock and use custom name
   local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
   if catalog_data then
      local unit_info = self._entity:add_component('stonehearth:unit_info')
      if unit_info:unlock(self._lock_key) then
         unit_info:set_display_name(self._charging_display_name)
         unit_info:set_custom_name(catalog_data.display_name, {
            percent_charge = math.floor(100*self._sv.charge/self._max_charge),
         }, true, true)
         unit_info:lock(self._lock_key)
      end
   end
   
   -- Are we done?
   if self._sv.charge >= self._max_charge then
      self:_stop_charge_timer()
      radiant.events.trigger(self._entity, 'stonehearth:amberstone:pedestal_charged')
   end
end

return AceAmberstoneChargingPedestalComponent
