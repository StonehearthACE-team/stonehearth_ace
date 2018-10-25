local MechanicalComponent = class()

local SCRIPTS_CACHE = {}

function MechanicalComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._json = json or {}
   self._sv.produces = self._json.produces or 0
   self._sv.consumes = self._json.consumes or 0
   self._sv.resistance = self._json.resistance or 0
   self._set_power_script = self._json.set_power_script
   self._enable_effect_name = self._json.enable_effect
   self._disable_effect_name = self._json.disable_effect
end

function MechanicalComponent:destroy()
   self:_destroy_listeners()
end

function MechanicalComponent:_destroy_listeners()
   if self._disable_effect then
		self._disable_effect:stop()
		self._disable_effect = nil
	end
	if self._enable_effect then
		self._enable_effect:stop()
		self._enable_effect = nil
	end
end

function MechanicalComponent:get_power_produced()
   return self._sv.produces
end

function MechanicalComponent:get_power_consumed()
   return self._sv.consumes
end

function MechanicalComponent:get_resistance()
   return self._sv.resistance
end

function MechanicalComponent:set_power_produced(amount)
   self._sv.produces = amount
   self.__saved_variables:mark_changed()
   self:_updated()
end

function MechanicalComponent:set_power_consumed(amount)
   self._sv.consumes = amount
   self.__saved_variables:mark_changed()
   self:_updated()
end

function MechanicalComponent:set_resistance(amount)
   self._sv.resistance = amount
   self.__saved_variables:mark_changed()
   self:_updated()
end

function MechanicalComponent:can_place_axle(axle)
   -- checks against connection client service to see if the positioning of the axle entity
   -- matches a connector from that entity with an available connector on this entity
   
end

function MechanicalComponent:_updated()
   radiant.events.trigger(self._entity, 'stonehearth_ace:mechanical:changed', self._entity)
end

function MechanicalComponent:set_power_percentage(percentage)
   if percentage > 0 then
      self:_run_enable_effect()
   else
      self:_run_disable_effect()
   end
   
   local script = self._set_power_script
   if script then
      if not SCRIPTS_CACHE[script] then
         SCRIPTS_CACHE[script] = radiant.mods.load_script(script)()
      end
      script = SCRIPTS_CACHE[script]

      if not script then
         radiant.verify(false, "Could not find script %s for mechanical entity %s", script, self._entity)
         return false
      end
      if not script.set_power_percentage then
         radiant.verify(false, "Could not find function set_power_percentage() for script %s for mechanical entity %s", script, self._entity)
         return false
      end
      return script.set_power_percentage(self._entity, percentage)
   end
end

function MechanicalComponent:_run_enable_effect()
   if self._disable_effect then
      self._disable_effect:stop()
      self._disable_effect = nil
   end
   if self._enable_effect_name and not self._enable_effect then
      self._enable_effect = radiant.effects.run_effect(self._entity, self._enable_effect_name)
         :set_cleanup_on_finish(false)
   end
end

function MechanicalComponent:_run_disable_effect()
   if self._enable_effect then
      self._enable_effect:stop()
      self._enable_effect = nil
   end
   if self._disable_effect_name and not self._disable_effect then
      self._disable_effect = radiant.effects.run_effect(self._entity, self._disable_effect_name)
         :set_cleanup_on_finish(false)
   end
end

return MechanicalComponent