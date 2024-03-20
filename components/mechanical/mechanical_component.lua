local MechanicalComponent = class()

local floor = math.floor

function MechanicalComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._json = json or {}
   self._def_produces = self._json.produces or 0
   self._def_consumes = self._json.consumes or 0
   self._def_resistance = self._json.resistance or 0

   self._sv.produces = self._def_produces
   self._sv.consumes = self._def_consumes
   self._sv.resistance = self._def_resistance
   self._sv.power_percentage = 0
   self._set_power_script = self._json.set_power_script
   self._enabled_effect_names = self._json.enabled_effects or {}
   self._disabled_effect_name = self._json.disabled_effect
   self._has_reverse_effects = self._json.has_reverse_effects or false
end

function MechanicalComponent:restore()
   self._is_restore = true
end

function MechanicalComponent:post_activate()
   if self._is_restore then
      self:set_power_percentage(self._sv.power_percentage)
   end
end

function MechanicalComponent:destroy()
   self:_destroy_listeners()
end

function MechanicalComponent:_destroy_listeners()
   if self._disabled_effect then
		self._disabled_effect:stop()
		self._disabled_effect = nil
	end
	if self._enabled_effect then
		self._enabled_effect:stop()
		self._enabled_effect = nil
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

function MechanicalComponent:set_power_produced(amount, should_reverse)
   self._sv.produces = amount
   if should_reverse ~= nil then
      self._sv.should_reverse_override = should_reverse
   end
   self:_updated()
end

function MechanicalComponent:set_power_produced_percent(percent, should_reverse)
   self:set_power_produced(percent * self._def_produces, should_reverse)
end

function MechanicalComponent:set_power_consumed(amount)
   self._sv.consumes = amount
   self:_updated()
end

function MechanicalComponent:set_power_consumed_percent(percent)
   self:set_power_consumed(percent * self._def_consumes)
end

function MechanicalComponent:set_resistance(amount)
   self._sv.resistance = amount
   self:_updated()
end

function MechanicalComponent:set_resistance_percent(percent)
   self:set_resistance(percent * self._def_resistance)
end

function MechanicalComponent:_updated()
   self.__saved_variables:mark_changed()
   radiant.events.trigger(self._entity, 'stonehearth_ace:mechanical:changed', self._entity)
end

-- this is called by the mechanical service on all mechanical entities in a network when that network's power is changed and calculated
function MechanicalComponent:set_power_percentage(percentage)
   if percentage > 0 then
      self:_run_enabled_effect(percentage)
   else
      self:_run_disabled_effect()
   end
   
   self._sv.power_percentage = percentage
   self.__saved_variables:mark_changed()

   self:_update_component_info()

   local script = self._set_power_script
   if script then
      local script = radiant.mods.require(script)

      if not script then
         radiant.verify(false, "Could not find script %s for mechanical entity %s", self._set_power_script, self._entity)
         return false
      end
      if not script.set_power_percentage then
         radiant.verify(false, "Could not find function set_power_percentage in script %s for mechanical entity %s", script, self._entity)
         return false
      end
      return script.set_power_percentage(self._entity, percentage)
   end
end

function MechanicalComponent:_get_enabled_effect(percentage)
   local result
   for effect, threshold in pairs(self._enabled_effect_names) do
      if not result then
         result = effect
      end

      if threshold > percentage then
         break
      else
         result = effect
      end
   end

   return result
end

function MechanicalComponent:set_should_reverse_override(value)
   self._sv.should_reverse_override = value
   self:set_power_percentage(self._sv.power_percentage)
end

function MechanicalComponent:_should_reverse()
   if self._has_reverse_effects then
      local override = self._sv.should_reverse_override
      if override ~= nil then
         return override
      end
      
      -- check entity facing
      local facing = radiant.entities.get_facing(self._entity) or 0
      return facing % 360 >= 180
   end

   return false
end

function MechanicalComponent:_run_enabled_effect(percentage)
   if self._disabled_effect then
      self._disabled_effect:stop()
      self._disabled_effect = nil
   end
   if self._enabled_effect then
      self._enabled_effect:stop()
      self._enabled_effect = nil
   end

   local effect_name = self:_get_enabled_effect(percentage)
   if effect_name then
      if self:_should_reverse() then
         local rev_effect_name = 'reverse_' .. effect_name
         if radiant.effects.has_effect(self._entity, rev_effect_name) then
            effect_name = rev_effect_name
         end
      end

      self._enabled_effect = radiant.effects.run_effect(self._entity, effect_name)
         :set_cleanup_on_finish(false)
   end
end

function MechanicalComponent:_run_disabled_effect()
   if self._enabled_effect then
      self._enabled_effect:stop()
      self._enabled_effect = nil
   end
   if self._disabled_effect_name and not self._disabled_effect then
      self._disabled_effect = radiant.effects.run_effect(self._entity, self._disabled_effect_name)
         :set_cleanup_on_finish(false)
   end
end

function MechanicalComponent:_update_component_info()
   local comp_info = self._entity:add_component('stonehearth_ace:component_info')

   if self._def_produces > 0 then
      comp_info:set_component_detail('stonehearth_ace:mechanical', 'produces',
         'stonehearth_ace:component_info.stonehearth_ace.mechanical.produces', {
            def_produces = floor(self._def_produces),
            produces = floor(self._sv.produces)
         })
   end
   if self._def_consumes > 0 then
      comp_info:set_component_detail('stonehearth_ace:mechanical', 'consumes',
         'stonehearth_ace:component_info.stonehearth_ace.mechanical.consumes', {
            def_consumes = floor(self._def_consumes),
            produces = floor(self._sv.consumes)
         })
   end
   if self._def_resistance > 0 then
      comp_info:set_component_detail('stonehearth_ace:mechanical', 'resistance',
         'stonehearth_ace:component_info.stonehearth_ace.mechanical.resistance', {
            def_resistance = floor(self._def_resistance),
            resistance = floor(self._sv.resistance)
         })
   end

   comp_info:set_component_detail('stonehearth_ace:mechanical', 'power_percentage',
      'stonehearth_ace:component_info.stonehearth_ace.mechanical.power_percentage', {
         power_percentage = floor(self._sv.power_percentage * 100)
      })
end

return MechanicalComponent