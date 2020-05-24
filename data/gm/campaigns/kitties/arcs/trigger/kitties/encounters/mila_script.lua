local RaycastLib = require 'stonehearth.ai.lib.raycast_lib'

local SpawnMilaScript = class()

function SpawnMilaScript:start(ctx, data)
   self._sv.player_id = ctx.player_id

   local npc_population = stonehearth.population:get_population('human_npcs')
   self._sv.mila = npc_population:create_new_citizen('kitten_mila', 'female')

   local town = stonehearth.town:get_town(ctx.player_id)
   local spawn_location = radiant.terrain.find_placement_point(town:get_landing_location(), 15, 50)
   radiant.terrain.place_entity(self._sv.mila, spawn_location)
   radiant.effects.run_effect(self._sv.mila, 'stonehearth:effects:spawn_entity')
   
   self:_set_combat_listener()
   
   self._sv.despawn_timer = stonehearth.calendar:set_persistent_timer('despawn mila', '7d', function()
         self:_despawn()
      end)
end

function SpawnMilaScript:_set_combat_listener()
   local player_population = stonehearth.population:get_population(self._sv.player_id)
   self._combat_listener = radiant.events.listen(player_population, 'stonehearth:population:engaged_in_combat', function(e)
         if radiant.entities.exists(self._sv.mila) and self._sv.mila:get_uri() ~= 'stonehearth_ace:monsters:forest:mila' then
            -- Transform.
            local old_mila = self._sv.mila
            local npc_population = stonehearth.population:get_population('human_npcs')
            self._sv.mila = npc_population:create_new_citizen('kitten_mila_protector', 'female')
            local spawn_location = radiant.entities.get_world_location(old_mila)
            radiant.terrain.place_entity_at_exact_location(self._sv.mila, spawn_location)
            radiant.effects.run_effect(self._sv.mila, 'stonehearth:effects:level_up')
            radiant.entities.destroy_entity(old_mila)
            self._sv.mila:set_player_id(self._sv.player_id)
            
            -- Go after the attacker.
            self._sv.mila:get_component('stonehearth:ai')
                  :get_task_group('stonehearth:task_groups:solo:combat_unit_control')
                     :create_task('stonehearth:goto_location', { location = radiant.entities.get_world_location(e.entity) })
                        :start()

            -- Start granting thoughts.
            self._thought_grant_interval = stonehearth.calendar:set_interval('grant mila thought', '15m', function()
               local friends = RaycastLib.get_visible_items_in_radius(radiant.entities.get_world_location(self._sv.mila), 20, function(e)
                     return e:get_player_id() == self._sv.player_id and e:get('stonehearth:thoughts')
                  end)
               for _, friend in pairs(friends) do
                  radiant.entities.add_thought(friend, 'stonehearth:thoughts:kitties:mila')
               end
            end)
            
            -- Cleanup.
            if self._combat_listener then
               self._combat_listener:destroy()
               self._combat_listener = nil
            end
            
            local threat_data = player_population._sv.threat_data
            self._threat_trace = threat_data:trace('mila combat end')
                                             :on_changed(function()
                                                   if not threat_data:get_data().in_combat then
                                                      self:_despawn()
                                                   end
                                                end)
         end
      end)
end

function SpawnMilaScript:restore()
   if self._sv.is_leaving then
      self:_despawn()
   else
      self:_set_combat_listener()
   end
end

function SpawnMilaScript:_despawn()
   if radiant.entities.exists(self._sv.mila) then
      self._sv.mila:get_component('stonehearth:ai')
            :get_task_group('stonehearth:task_groups:solo:unit_control')
               :create_task('stonehearth:depart_visible_area', { give_up_after = '4h' })
                  :start()
      self._sv.is_leaving = true
   else
      self._sv.mila = nil
      self._sv.is_leaving = nil
   end

   if self._sv.despawn_timer then
      self._sv.despawn_timer:destroy()
      self._sv.despawn_timer = nil
   end
   if self._combat_listener then
      self._combat_listener:destroy()
      self._combat_listener = nil
   end
   if self._thought_grant_interval then
      self._thought_grant_interval:destroy()
      self._thought_grant_interval = nil
   end
   if self._threat_trace then
      self._threat_trace:destroy()
      self._threat_trace = nil
   end
end

return SpawnMilaScript
