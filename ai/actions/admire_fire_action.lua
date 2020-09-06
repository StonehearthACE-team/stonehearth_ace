local AdmireFire = radiant.class()

AdmireFire.name = 'admire fire'
AdmireFire.args = {}
AdmireFire.does = 'stonehearth:admire_fire'
AdmireFire.status_text_key = 'stonehearth:ai.actions.status_text.resting_by_fire'
AdmireFire.priority = 0

function AdmireFire:start_thinking(ai, entity, args)
   --local player_id = radiant.entities.get_player_id(entity)
	local work_player_id = radiant.entities.get_work_player_id(entity)

   self._entity = entity
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:admire_fire', work_player_id, function(item)
         local fire_player_id = radiant.entities.get_player_id(item)
         if fire_player_id ~= work_player_id and not radiant.entities.is_material(entity, 'friendly_npc') then
            return false
         end

         local center_of_attention_spot_component = item:get_component('stonehearth:center_of_attention_spot')
         if center_of_attention_spot_component then
            local center_of_attention = center_of_attention_spot_component:get_center_of_attention()
            if center_of_attention then
               local firepit_component = center_of_attention:get_component('stonehearth:firepit')
               if firepit_component and firepit_component:is_lit() then
                  return true
               end
            end
         end
         --To get here, there is either no lease, the lease is taken or it's not a friendly fire
         --or it is but the fire isn't lit
         return false
      end)

   ai:set_think_output({
         filter_fn = filter_fn,
			owner_player_id = work_player_id,
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(AdmireFire)
            :execute('stonehearth:drop_carrying_now', {})
            :execute('stonehearth:goto_entity_type', {
               description = 'find lit fire',
               filter_fn = ai.BACK(2).filter_fn,
            })
            :execute('stonehearth:reserve_entity', { 
					entity = ai.PREV.destination_entity, 
					owner_player_id = ai.BACK(3).owner_player_id,
				})
            :execute('stonehearth:admire_fire_adjacent', { seat = ai.BACK(1).entity })
