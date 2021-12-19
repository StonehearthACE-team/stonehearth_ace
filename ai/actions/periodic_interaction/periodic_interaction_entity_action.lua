local Entity = _radiant.om.Entity
local InteractWithItem = radiant.class()

InteractWithItem.name = 'periodic_interaction'
InteractWithItem.does = 'stonehearth_ace:periodic_interaction'
InteractWithItem.args = {}
InteractWithItem.priority = 1.0

local log = radiant.log.create_logger('periodic_interaction_entity_action')

function InteractWithItem:start_thinking(ai, entity, args)
   self._on_consider_usability = radiant.events.listen(entity, 'stonehearth_ace:periodic_interaction:became_usable', function(item, mode)
         local periodic_interaction_comp = item:get_component('stonehearth_ace:periodic_interaction')
         if periodic_interaction_comp and periodic_interaction_comp:is_enabled() and periodic_interaction_comp:get_current_mode() == mode then
            local user = periodic_interaction_comp:get_current_user()
            if not user or user == entity then
               --log:debug('%s considering interacting with %s...', entity, item)
               ai:set_think_output({ item = item })
               self:_destroy_listener()
            end
         end
      end)
end

function InteractWithItem:stop_thinking(ai, entity, args)
   self:_destroy_listener()
end

function InteractWithItem:_destroy_listener()
   if self._on_consider_usability then
      self._on_consider_usability:destroy()
      self._on_consider_usability = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(InteractWithItem)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.BACK(3).item,
            event_name = 'stonehearth_ace:periodic_interaction:cancel_usage',
         })
         :execute('stonehearth:reserve_entity', { entity = ai.BACK(4).item })
         :execute('stonehearth:goto_entity', { entity = ai.BACK(5).item })
         :execute('stonehearth_ace:periodic_interaction_adjacent', { item = ai.BACK(6).item })
