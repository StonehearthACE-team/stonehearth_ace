local GUTS_RESOURCE_NAME = 'guts'
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
         local expendable_resource_component = entity:get_component('stonehearth:expendable_resources')
         local guts_value = expendable_resource_component:get_value(GUTS_RESOURCE_NAME)
         local ic_data = radiant.entities.get_entity_data(entity, 'stonehearth:incapacitate_data')

         local initial_subtraction = (ic_data.on_incapacitate_guts_subtraction or 1)
          if radiant.entities.has_job_perk(self._entity, 'trapper_master_survivalist') then
            initial_subtraction = 1
         end

         expendable_resource_component:modify_value(GUTS_RESOURCE_NAME,  -(initial_subtraction))

         radiant.events.trigger_async(entity, 'stonehearth:entity:became_incapacitated', { entity = entity })
         local auto_rescue = stonehearth.client_state:get_client_gameplay_setting(entity:get_player_id(), 'stonehearth', 'auto_rescue', false)
         if auto_rescue then
            self:_toggle_rescue()
         end

      end
end

AceIncapacitationComponent._ace_old__declare_state_event_handlers = IncapacitationComponent._declare_state_event_handlers
function AceIncapacitationComponent:_declare_state_event_handlers(sm)
   self:_ace_old__declare_state_event_handlers(sm)

   sm._states[STATES.RECUPERATING]['hourly'] = function(event_args, event_source)
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
