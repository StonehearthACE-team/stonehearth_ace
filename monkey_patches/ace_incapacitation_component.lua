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

return AceIncapacitationComponent
