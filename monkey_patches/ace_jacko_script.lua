local AceSpawnJackoScript = class()

function AceSpawnJackoScript:restore()
   self._is_restore = true
end

function AceSpawnJackoScript:post_activate()
   if not self._is_restore then
      return
   end

   if self._sv.is_leaving then
      self:_despawn()
   elseif radiant.entities.exists(self._sv.jacko) and self._sv.jacko:get_uri() == 'stonehearth:monsters:forest:jacko' then
      -- saved as the protector: the thought interval and the combat-end trace are not saved
      if not self:_start_protecting() then
         self:_despawn()   -- the town is not in combat after the load: leave, as the trace would have made her
      end
   else
      self:_set_combat_listener()
   end
end

function AceSpawnJackoScript:_set_combat_listener()
   local player_population = stonehearth.population:get_population(self._sv.player_id)
   self._combat_listener = radiant.events.listen(player_population, 'stonehearth:population:engaged_in_combat', function(e)
         if radiant.entities.exists(self._sv.jacko) and self._sv.jacko:get_uri() ~= 'stonehearth:monsters:forest:jacko' then
            -- Transform.
            local old_jacko = self._sv.jacko
            local npc_population = stonehearth.population:get_population('human_npcs')
            self._sv.jacko = npc_population:create_new_citizen('kitten_jacko_protector', 'male')
            local spawn_location = radiant.entities.get_world_location(old_jacko)
            radiant.terrain.place_entity_at_exact_location(self._sv.jacko, spawn_location)
            radiant.effects.run_effect(self._sv.jacko, 'stonehearth:effects:lightning_blast')
            radiant.entities.destroy_entity(old_jacko)
            self._sv.jacko:set_player_id(self._sv.player_id)
            
            -- Go after the attacker.
            self._sv.jacko:get_component('stonehearth:ai')
                  :get_task_group('stonehearth:task_groups:solo:combat_unit_control')
                     :create_task('stonehearth:goto_location', { location = radiant.entities.get_world_location(e.entity) })
                        :start()

            -- Start granting thoughts.
            self:_start_protecting()
            
            -- Cleanup.
            if self._combat_listener then
               self._combat_listener:destroy()
               self._combat_listener = nil
            end
         end
      end)
end

function AceSpawnJackoScript:_start_protecting()
   -- Start granting thoughts.
   self._thought_grant_interval = stonehearth.calendar:set_interval('grant jacko thought', '15m', function()
      local friends = RaycastLib.get_visible_items_in_radius(radiant.entities.get_world_location(self._sv.jacko), 20, function(e)
            return e:get_player_id() == self._sv.player_id and e:get('stonehearth:thoughts')
         end)
      for _, friend in pairs(friends) do
         radiant.entities.add_thought(friend, 'stonehearth:thoughts:kitties:jacko')
      end
   end)

   local threat_data = stonehearth.population:get_population(self._sv.player_id)._sv.threat_data
   self._threat_trace = threat_data:trace('jacko combat end')
                                    :on_changed(function()
                                          if not threat_data:get_data().in_combat then
                                             self:_despawn()
                                          end
                                       end)
   return threat_data:get_data().in_combat
end

return AceSpawnJackoScript
