local AceAuraBuff = class()

function AceAuraBuff:_on_pulse()
   local player_id = radiant.entities.get_player_id(self._entity)
   local num_affected = 0
   -- get everyone around us
	
   local aura_buffs = self._tuning.aura_buff
	if type(aura_buffs) == 'string' then
      aura_buffs = { aura_buffs }
   end
	
   local sensor_name = self._tuning.sensor_name or 'sight'
   local sensor = self._entity:add_component('sensor_list'):get_sensor(sensor_name)
   local enemies_within_range = false
   local target_entities = {}
   for id, target in sensor:each_contents() do
      if id ~= self._entity:get_id() or self._tuning.affect_self then
         local target_player_id = radiant.entities.get_player_id(target)
				if stonehearth.player:are_player_ids_friendly(player_id, target_player_id) or stonehearth.player:are_player_ids_hostile(player_id, target_player_id) and self._tuning.target_enemies then
					local can_target = true
					-- If we can only target specific type of entity, make sure the entity's target_type matches
					if self._tuning.target_type then
						if radiant.entities.get_target_type(target) ~= self._tuning.target_type then
							can_target = false
						end
					end
					if not self:_is_within_range(target) then
						can_target = false
					end
	
					if can_target then
						table.insert(target_entities, target)
					end
				elseif self._tuning.emit_if_enemies_nearby and not enemies_within_range and stonehearth.player:are_player_ids_hostile(player_id, target_player_id) then
					if self:_is_within_range(target) then
               enemies_within_range = true
					end
         end
      end
   end

   if self._tuning.emit_if_enemies_nearby and not enemies_within_range then
      return -- buff needs enemies to be nearby in order to emit the aura buff
   end

   for _, target in ipairs(target_entities) do
		for _, aura_buff in ipairs(aura_buffs) do
			radiant.entities.add_buff(target, aura_buff)
			if radiant.entities.has_buff(target, aura_buff) then
				num_affected = num_affected + 1
			end
		end
   end

   if num_affected > 0 and self._tuning and self._tuning.pulse_effect then
      radiant.effects.run_effect(self._entity, self._tuning.pulse_effect)
   end
end

return AceAuraBuff
