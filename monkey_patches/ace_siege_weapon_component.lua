local AceSiegeWeaponComponent = class()

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
   if self:needs_refill() then
      radiant.events.trigger(self._entity, 'stonehearth:siege_weapon:needs_refill')
   end
   self.__saved_variables:mark_changed()
end

return AceSiegeWeaponComponent
