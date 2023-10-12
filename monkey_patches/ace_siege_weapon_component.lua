local SiegeWeaponComponent = require 'stonehearth.components.siege_weapon.siege_weapon_component'
local AceSiegeWeaponComponent = class()

AceSiegeWeaponComponent._ace_old_activate = SiegeWeaponComponent.activate
function AceSiegeWeaponComponent:activate()
   self:_ace_old_activate()

   if self._json.passive_refill and not self._interval_listener then
      local interval = self._json.passive_refill.interval or "30m"
      local amount = self._json.passive_refill.amount or 1
      self._interval_listener = stonehearth.calendar:set_interval("Siege Weapon passive refilling "..self._entity:get_id().." interval", interval, 
            function()
               self:_on_interval(amount)
            end)
   end
end

function AceSiegeWeaponComponent:_on_interval(amount)
   if not self:needs_refill() then
      return
   end

   self:refill_uses(amount)
end

-- Subtract from num uses when target is hit with ammo
-- When no more uses, run destroy animation and destroy self
function AceSiegeWeaponComponent:_on_target_hit(context)
   local json = self._json or radiant.entities.get_json(self)
   local disposable = json and json.disposable or false
   local num_uses = self._sv.num_uses - 1
   if num_uses <= 0 then
      if disposable then
         radiant.entities.kill_entity(self._entity)
      end
      self._out_of_ammo = true
   end
   self._sv.num_uses = num_uses
   if self:needs_refill() and not self._json.passive_refill then
      radiant.events.trigger(self._entity, 'stonehearth:siege_weapon:needs_refill')
   end
   self.__saved_variables:mark_changed()
end

AceSiegeWeaponComponent._ace_old__destroy_traces = SiegeWeaponComponent._destroy_traces
function AceSiegeWeaponComponent:_destroy_traces()
   if self._interval_listener then
      self._interval_listener:destroy()
      self._interval_listener = nil
   end

   self:_ace_old__destroy_traces()
end

return AceSiegeWeaponComponent
