local SpawnFriendlyStranger = class()

function SpawnFriendlyStranger:start(ctx, data)
   local npc_population = stonehearth.population:get_population(data.npc_player_id)
	self._sv.friendly_strangers = {}
	for citizen, gender in pairs(data.citizens) do
		local friendly_stranger = npc_population:create_new_citizen(citizen, gender)
      local work_order_comp = friendly_stranger:add_component('stonehearth:work_order')
      work_order_comp:set_working_for_player_id(ctx.player_id)
		table.insert(self._sv.friendly_strangers, friendly_stranger)
	end

   local town = stonehearth.town:get_town(ctx.player_id)
	for _, stranger in ipairs(self._sv.friendly_strangers) do
		local spawn_location = radiant.terrain.find_placement_point(town:get_landing_location(), 25, 50)
		radiant.terrain.place_entity(stranger, spawn_location)
		radiant.effects.run_effect(stranger, 'stonehearth:effects:spawn_entity')
	end

   self._sv.despawn_timer = stonehearth.calendar:set_persistent_timer('despawn friendly stranger', '1d', radiant.bind(self, '_despawn'))
end

function SpawnFriendlyStranger:_despawn()
	for _, stranger in ipairs(self._sv.friendly_strangers) do
		if radiant.entities.exists(stranger) then
			stranger:get_component('stonehearth:ai')
					:get_task_group('stonehearth:task_groups:solo:unit_control')
						:create_task('stonehearth:depart_visible_area', { give_up_after = '2h' })
							:start()
		end
	end
	
   if self._sv.despawn_timer then
      self._sv.despawn_timer:destroy()
      self._sv.despawn_timer = nil
   end
end

return SpawnFriendlyStranger