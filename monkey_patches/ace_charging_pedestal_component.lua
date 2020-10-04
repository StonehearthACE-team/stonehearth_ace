-- Accumulates charges over time while placed in the world, and emits
-- a "stonehearth:amberstone:pedestal_charged" event on the entity when
-- MAX_CHARGE is reached.
local AceAmberstoneChargingPedestalComponent = radiant.class()

local MAX_CHARGE = 70
local CHARGE_PER_HOUR = 2

function AceAmberstoneChargingPedestalComponent:_charge()
   -- Make sure we are deployed.
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   -- TODO: Check that we aren't underground.

   -- Charge.  ACE: cap it at MAX_CHARGE
   self._sv.charge = math.min(MAX_CHARGE, self._sv.charge + CHARGE_PER_HOUR)
   self.__saved_variables:mark_changed()
   
   -- Update name to indicate charging status.
   -- TODO: This need a real solution that support i18n.
   local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
   if catalog_data then
      radiant.entities.set_display_name(self._entity, catalog_data.display_name .. ' [' .. math.floor(100*self._sv.charge/MAX_CHARGE) .. '%]')
   end
   
   -- Are we done?
   if self._sv.charge >= MAX_CHARGE then
      self:_stop_charge_timer()
      radiant.events.trigger(self._entity, 'stonehearth:amberstone:pedestal_charged')
   end
end

return AceAmberstoneChargingPedestalComponent
