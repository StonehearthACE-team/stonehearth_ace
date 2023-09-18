local GUTS_RESOURCE_NAME = 'guts'
local ADDITIVE_GUTS_SUBTRACTION_MODIFIER_ATTRIBUTE = 'additive_guts_subtraction_modifier'
local log = radiant.log.create_logger('incapacitation_component')

local IncapacitationComponent = require 'stonehearth.components.incapacitation.incapacitation_component'
local AceIncapacitationComponent = class()

local STATES = {
   NORMAL = 'normal',
   AWAITING_RESCUE = 'awaiting_rescue',
   RESCUING = 'rescuing',
   RECUPERATING = 'recuperating',
   DEAD = 'dead',
}

function AceIncapacitationComponent:_drop_equipment()
   local location = radiant.entities.get_world_grid_location(self._entity)

   if not location then
      return
   end

   -- Drop all equipment that is droppable.
   local ec = self._entity:get_component('stonehearth:equipment')
   local equipped_items = ec and ec:get_all_dropable_items() or {}

   for key, item in pairs(equipped_items) do
      ec:unequip_item(item)
      -- drop_item will destroy any items that are destroy_on_drop
      ec:drop_item(item)
   end

   -- If you have a job, re-equip your default equipment.
   local jc = self._entity:get_component('stonehearth:job')
   if jc and ec then
      jc:_equip_equipment(jc:get_job_data(), jc:get_current_talisman_uri())
   end
end

AceIncapacitationComponent._ace_old__declare_state_transitions = IncapacitationComponent._declare_state_transitions
function AceIncapacitationComponent:_declare_state_transitions(sm)
   self:_ace_old__declare_state_transitions(sm)
   
   -- we're overriding a transition we just set up, and apparently the state machine doesn't allow that,
   -- nor does it allow removing a state transition! so we'll just have to manually hack it in
   sm._full_transitions[STATES.NORMAL][STATES.AWAITING_RESCUE] = function()
         local entity = self._entity

         self:_drop_carried()

         entity:get_component('mob'):set_has_free_will(false)
         stonehearth.physics:unstick_entity(entity)

         radiant.entities.add_buff(entity, 'stonehearth:buffs:incapacitated')

         -- set guts to 75%
         -- (ACE) Add some flexbility for some possible "guts" altering modifiers to be supported; subtraction limited to a value between 1 and max_guts-1 (23 with default base human values)
         local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
         local attributes_component = entity:get_component('stonehearth:attributes')
         local guts_value = expendable_resource_component:get_value(GUTS_RESOURCE_NAME)
         local additive_guts_subtraction_modifier = attributes_component:get_attribute(ADDITIVE_GUTS_SUBTRACTION_MODIFIER_ATTRIBUTE) or 0
         local ic_data = radiant.entities.get_entity_data(entity, 'stonehearth:incapacitate_data')
         
         local initial_subtraction = 1
         
         if radiant.entities.has_job_perk(entity, 'trapper_master_survivalist') then
            -- (ACE) Trapper perk will also half the modifiers, but only if they're positive (negative modifiers are a buff)
            if additive_guts_subtraction_modifier > 0 then
               initial_subtraction = math.max(1, math.floor((additive_guts_subtraction_modifier + 0.5) / 2))
            else
               initial_subtraction = math.max(1, math.floor((additive_guts_subtraction_modifier + 0.5)))
            end
         else
            initial_subtraction = math.max(1, (ic_data.on_incapacitate_guts_subtraction or 1) + additive_guts_subtraction_modifier)
         end
         
         initial_subtraction = math.min(initial_subtraction, guts_value - 1)

         expendable_resource_component:modify_value(GUTS_RESOURCE_NAME,  -(initial_subtraction))

         radiant.events.trigger_async(entity, 'stonehearth:entity:became_incapacitated', { entity = entity })
         local auto_rescue = stonehearth.client_state:get_client_gameplay_setting(entity:get_player_id(), 'stonehearth', 'auto_rescue', false)
         if auto_rescue then
            self:_toggle_rescue()
         end

      end

   -- if they were already in a bed when they became incapacitated, make sure the same stuff happens as if they were rescued into the bed
   sm:on_state_transition(STATES.NORMAL, STATES.RECUPERATING, function()
         local entity = self._entity

         entity:get_component('mob'):set_has_free_will(false)

         radiant.entities.add_buff(entity, 'stonehearth:buffs:incapacitated')

         -- set guts to 75%
         -- (ACE) Add some flexbility for some possible "guts" altering modifiers to be supported; subtraction limited to a value between 1 and max_guts-1 (23 with default base human values)
         local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
         local attributes_component = entity:get_component('stonehearth:attributes')
         local guts_value = expendable_resource_component:get_value(GUTS_RESOURCE_NAME)
         local additive_guts_subtraction_modifier = attributes_component:get_attribute(ADDITIVE_GUTS_SUBTRACTION_MODIFIER_ATTRIBUTE) or 0
         local ic_data = radiant.entities.get_entity_data(entity, 'stonehearth:incapacitate_data')
         
         local initial_subtraction = 1
         
         if radiant.entities.has_job_perk(entity, 'trapper_master_survivalist') then
            -- (ACE) Trapper perk will also half the modifiers, but only if they're positive (negative modifiers are a buff)
            if additive_guts_subtraction_modifier > 0 then
               initial_subtraction = math.max(1, math.floor((additive_guts_subtraction_modifier + 0.5) / 2))
            else
               initial_subtraction = math.max(1 + additive_guts_subtraction_modifier)
            end
         else
            initial_subtraction = math.max(1, (ic_data.on_incapacitate_guts_subtraction or 1) + additive_guts_subtraction_modifier)
         end
         
         initial_subtraction = math.min(initial_subtraction, guts_value - 1)

         expendable_resource_component:modify_value(GUTS_RESOURCE_NAME,  -(initial_subtraction))

         radiant.events.trigger_async(entity, 'stonehearth:entity:became_incapacitated', { entity = entity })
         
         self:_drop_equipment()

         radiant.entities.add_buff(entity, 'stonehearth:buffs:recuperating')
         radiant.entities.remove_buff(entity, 'stonehearth:buffs:incapacitated')

         -- ACE: have to do this next frame now that it's at the same time as reducing it
         -- radiant.on_game_loop_once('incapacitated in bed, increase guts', function()
         --       -- Kick the guts resouce up _slightly_, so that the hearthling's guts overlay shows it is now
         --       -- increasing.
         --       expendable_resource_component:modify_value(GUTS_RESOURCE_NAME, 0.1)
         --    end)
      end)
end

AceIncapacitationComponent._ace_old__declare_state_event_handlers = IncapacitationComponent._declare_state_event_handlers
function AceIncapacitationComponent:_declare_state_event_handlers(sm)
   self:_ace_old__declare_state_event_handlers(sm)

   sm._states[STATES.NORMAL].state_fns['stonehearth:expendable_resource_changed:health'] = function(event_args, event_source)
         local health = radiant.entities.get_health(self._entity)
         if health and health <= 0 then
            if radiant.entities.has_buff(self._entity, 'stonehearth:buffs:starving') and not radiant.entities.is_in_combat(self._entity) then
               -- We've starved to death--probably?  it's slightly hard to tell, but this is probably close enough.
               -- No incapacitation for you!
               sm:go_into(STATES.DEAD)
               return
            end

            -- if already in a bed, they don't need to be rescued; skip to recuperating
            local parent = radiant.entities.get_parent(self._entity)
            local bed_data = parent and radiant.entities.get_entity_data(parent, 'stonehearth:bed')
            local mount = parent and parent:get_component('stonehearth:mount')
            if bed_data and mount and mount:get_user() == self._entity then
               log:debug('already in bed; going to state "recuperating"')
               sm:go_into(STATES.RECUPERATING)
            else
               log:debug('not already in bed; going to state "awaiting_rescue"')
               sm:go_into(STATES.AWAITING_RESCUE)
            end
         end
      end

   sm._states[STATES.RECUPERATING].state_fns['hourly'] = function(event_args, event_source)
         -- if we have been rescued, then our guts no longer go down
         -- Increase our guts based on where we are:
         local guts_recovery_data = self._ic_data.rescued_guts_hourly_recovery
         local hourly_increase = guts_recovery_data['on_ground']
         local parent = radiant.entities.get_parent(self._entity)
         if parent and parent:is_valid() then
            local bed_data = radiant.entities.get_entity_data(parent, 'stonehearth:bed')
            if bed_data then
               local mount_component = parent:get_component('stonehearth:mount')
               if mount_component and mount_component:get_user() == self._entity then
                  if bed_data.priority_care then
                     hourly_increase = guts_recovery_data['in_priority_care_bed']
                  else
                     local object_owner_component = self._entity:get_component('stonehearth:object_owner')
                     local bed = object_owner_component and object_owner_component:get_owned_object('bed')
                     -- check if sleeping in own bed versus just any bed

                     if bed == parent then
                        hourly_increase = guts_recovery_data['in_own_bed']
                     else
                        hourly_increase = guts_recovery_data['in_unowned_bed']
                     end
                  end
               end
            end
         end

         local expendable_resource_component = self._entity:get_component('stonehearth:expendable_resources')
         expendable_resource_component:modify_value(GUTS_RESOURCE_NAME, hourly_increase)
      end
end

return AceIncapacitationComponent
