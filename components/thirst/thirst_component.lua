local ThirstComponent = class()

function ThirstComponent:activate()
   self._is_thirsty = false
	self._is_very_thirsty = false
   self._consumption = self._entity:get_component('stonehearth:consumption')
   assert(self._consumption)
   self._drink_satiety_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:drink_satiety', self, self._on_drink_satiation_changed)

   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
         self:_adjust_status()
         self._game_loaded_listener = nil
      end)
end

function ThirstComponent:destroy()
   if self._drink_satiety_listener then
      self._drink_satiety_listener:destroy()
      self._drink_satiety_listener = nil
   end

   if self._game_loaded_listener then
      self._game_loaded_listener:destroy()
      self._game_loaded_listener = nil
   end
end

function ThirstComponent:_on_drink_satiation_changed()
   self:_adjust_status()
end

function ThirstComponent:_adjust_status()
   local thirst_state = self._consumption:get_drink_satiety_state()

   if thirst_state == stonehearth.constants.drink_satiety_levels.SATED then
      radiant.entities.add_thought(self._entity, 'stonehearth_ace:thoughts:thirst:sated')
   elseif thirst_state == stonehearth.constants.drink_satiety_levels.VERY_THIRSTY then
      radiant.entities.add_thought(self._entity, 'stonehearth_ace:thoughts:thirst:very_thirsty')
   elseif thirst_state == stonehearth.constants.drink_satiety_levels.THIRSTY then
      radiant.entities.add_thought(self._entity, 'stonehearth_ace:thoughts:thirst:thirsty')
   else
      radiant.entities.add_thought(self._entity, 'stonehearth_ace:thoughts:thirst:neutral')
   end

   local population = stonehearth.population:get_population(self._entity)
	if thirst_state == stonehearth.constants.drink_satiety_levels.VERY_THIRSTY then
      if not self._is_very_thirsty then
         self._is_very_thirsty = true
			self._is_thirsty = false
			radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:thirsty')
         radiant.entities.add_buff(self._entity, 'stonehearth_ace:buffs:consumption:very_thirsty')
      end
   elseif thirst_state == stonehearth.constants.drink_satiety_levels.THIRSTY then
      if not self._is_thirsty then
		   self._is_very_thirsty = false
         self._is_thirsty = true
			radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:very_thirsty')
         radiant.entities.add_buff(self._entity, 'stonehearth_ace:buffs:consumption:thirsty')
      end
   else
      if self._is_very_thirsty then
			self._is_very_thirsty = false
			radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:very_thirsty')
      elseif self._is_thirsty then
			self._is_thirsty = false
			radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:thirsty')
		elseif radiant.entities.has_buff(self._entity, 'stonehearth_ace:buffs:consumption:thirsty') or radiant.entities.has_buff(self._entity, 'stonehearth_ace:buffs:consumption:very_thirsty') then
			radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:very_thirsty')
         radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:consumption:thirsty')
		end
   end
end

return ThirstComponent
