--[[
   primary usage is consuming fuel for workbenches:
   tracks how much fuel it has (could use container_component, but might bloat that with added functionality - maybe TODO?)
   fuel can be set to passively decay over time, with limits
]]

local ConsumerComponent = class()

function ConsumerComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}

   -- this gets set to the required level for crafting an item when the forge is fueled for it
   self._sv.min_decay_fuel_level = 0
end

function ConsumerComponent:create()
   self._is_create = true
end

function ConsumerComponent:activate()
   self:_initialize_fuel_settings()
   
   if self._is_create then
      self:_set_fuel_level(self._json.start_level or 0)
   else
      self:_renew_effects()
   end
end

function ConsumerComponent:destroy()
   if self._fuel_decay_timer then
      self._fuel_decay_timer:destroy()
      self._fuel_decay_timer = nil
   end
end

function ConsumerComponent:_initialize_fuel_settings()
   if self._json.time_decay and self._json.time_decay.interval then
      self._fuel_decay_timer = stonehearth.calendar:set_interval('workshop fuel decay', self._json.time_decay.interval, function()
         self:_on_fuel_decay()
      end)
   end

   -- fuels are specified with a uri or material
   -- they contain fields like amount, max_level
   self._fuels = self._json.fuels or {}
end

function ConsumerComponent:_on_fuel_decay()
   local decay_settings = self._json.time_decay
   local min_level = math.max(decay_settings.min_level or 0, self._sv.min_decay_fuel_level)
   local cur_level = self._sv.fuel_level
   local change = decay_settings.amount or (decay_settings.relative_amount and math.ceil(decay_settings.relative_amount * cur_level)) or 0
   local new_level = math.max(min_level, cur_level - change)

   if new_level < cur_level then
      self:_set_fuel_level(new_level)
   end
end

-- TODO? maybe add max_level setting to the component as a whole
local function _calc_new_fuel_level(level, fuel_data)
   local new_level = level + (fuel_data.amount or (fuel_data.relative_amount and fuel_data.relative_amount * math.max(1, level))) or 0
   if fuel_data.max_level then
      new_level = math.min(new_level, fuel_data.max_level)
   end
   return new_level
end

function ConsumerComponent:get_fuel_level()
   return self._sv.fuel_level
end

function ConsumerComponent:get_current_variant_tier()
   return self._sv._variant_tier
end

-- figure out how much fuel is needed to get it to the right level
-- set the min decay level to the required level minus that fuel level
function ConsumerComponent:request_fuel_level(level)

end

function ConsumerComponent:add_fuel(fuel)
   -- first check if the uri is specified
   local fuel_data = self._fuels[fuel:get_uri()]
   local cur_level = self._sv.fuel_level
   local new_level
   if fuel_data then
      new_level = _calc_new_fuel_level(cur_level, fuel_data)
   else
      -- if not, check fuel data materials and get the highest match
      for materials, fd in pairs(self._fuels) do
         if radiant.entities.is_material(fuel, materials) then
            local newer_level = _calc_new_fuel_level(cur_level, fd)
            if not new_level or newer_level > new_level then
               fuel_data = fd
               new_level = newer_level
            end
         end
      end
      -- cache it so we don't have to do this again for the same fuel material
      self._fuels[fuel:get_uri()] = fuel_data
   end

   if new_level and new_level > cur_level then
      self:_set_fuel_level(new_level)
   end
end

function ConsumerComponent:reduce_fuel_level(amount, keep_min_decay_level)
   local cur_level = self._sv.fuel_level
   local min_level = self._json.time_decay.min_level or 0
   local new_level = math.max(min_level, cur_level - amount)
   if new_level < cur_level then
      if not keep_min_decay_level then
         self._sv.min_decay_fuel_level = min_level
      end
      self:_set_fuel_level(new_level)
   end
end

function ConsumerComponent:set_min_decay_fuel_level(level)
   self._sv.min_decay_fuel_level = level
   self.__saved_variables:mark_changed()
end

function ConsumerComponent:_set_fuel_level(level)
   self._sv.fuel_level = level
   self.__saved_variables:mark_changed()

   if self._json.variant_tiers then
      -- each variant tier can specify a model_variant, an effect, a transition_from_lower_effect, and a transition_from_higher_effect
      -- variant tiers are sticky: min/max values can overlap, and when you're in one, you stay in it until you go past one of the bounds
      -- this prevents bouncing back and forth between models/effects when right on the edge (you can still specify strict edges if you want)
      local current_tier = self._sv._variant_tier
      if current_tier then
         -- if we're already in a variant tier, check to see if we're still in the bounds
         if (not current_tier.min_level or level >= current_tier.min_level) and (not current_tier.max_level or level <= current_tier.max_level) then
            return
         end

         for _, tier in ipairs(self._json.variant_tiers) do
            if (not tier.min_level or level >= tier.min_level) and (not tier.max_level or level <= tier.max_level) then
               self._sv._variant_tier = tier
               self.__saved_variables:mark_changed()
               
               local transition
               if current_tier.min_level and level < current_tier.min_level then
                  transition = tier.transition_from_higher_effect
               elseif current_tier.max_level and level > current_tier.max_level then
                  transition = tier.transition_from_lower_effect
               end

               self:_renew_effects(transition)

               radiant.events.trigger(self._entity, 'stonehearth_ace:consumer:fuel_level_changed', {level = level, old_tier = current_tier, new_tier = tier})

               return
            end
         end
      end
   end

   radiant.events.trigger(self._entity, 'stonehearth_ace:consumer:fuel_level_changed', {level = level})
end

function ConsumerComponent:_renew_effects(transition)
   local variant_tier = self._sv._variant_tier
   if variant_tier then
      self:_run_effect(variant_tier.effect, variant_tier.model_variant, transition)
   end
end

function ConsumerComponent:_run_effect(effect, model_variant, transition)
   if self._effect then
      self._effect:destroy()
      self._effect = nil
   end

   if transition then
      self._effect = radiant.effects.run_effect(self._entity, transition):set_finished_cb(function()
         self:_run_effect(effect, model_variant)
      end)
   else
      if model_variant then
         self._entity:add_component('stonehearth_ace:entity_modification'):set_model_variant(model_variant)
      end
      if effect then
         self._effect = radiant.effects.run_effect(self._entity, effect)
      end
   end
end

return ConsumerComponent
