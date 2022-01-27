--[[
   NOT BEING USED; for now, trying to rely on normal item-finder filters/actions
   Similar to craft_items_orchestrator. Observes periodic_interaction entities that register with the town,
   listening to when they're available for use, determining valid users, and creating tasks for them.
]]

local PeriodicInteractionOrchestrator

local log = radiant.log.create_logger('periodic_interaction'):set_prefix('orchestrator')

function PeriodicInteractionOrchestrator:run(town, args)
   self._town = town
   self._entity = args.entity
   self:_setup_listeners()

   self._task_group = stonehearth.tasks:instantiate_task_group('stonehearth_ace:task_groups:orchestrated_periodic_interaction')
                                                  :add_worker(self._entity)

   while true do
      -- 
   end
end

function PeriodicInteractionOrchestrator:destroy()
   self:_destroy_task()
   if self._retry_listener then
      self._retry_listener:destroy()
      self._retry_listener = nil
   end
end

function PeriodicInteractionOrchestrator:_setup_listeners()
   self._entity_listeners = {}
   for id, pi_entity in pairs(self._town:get_periodic_interaction_entities()) do
      self:_setup_entity_listener(pi_entity)
   end

   self._entity_added_listener = radiant.events.listen(self._town, 'stonehearth_ace:periodic_interaction:entity_added', function (entity)
         self:_setup_entity_listener(entity)
      end)
end

function PeriodicInteractionOrchestrator:_setup_entity_listener(entity)
   local id = entity:get_id()
   if not self._entity_listeners[id] then
      self._entity_listeners[id] = radiant.events.listen(entity, 'stonehearth_ace:periodic_interaction:became_usable', function(mode)
         self:_entity_became_usable(entity, mode)
      end)
   end
end

function PeriodicInteractionOrchestrator:_entity_became_usable(entity, mode)
   self:_try_choosing_entity(entity)
end

function PeriodicInteractionOrchestrator:_try_choosing_entity(entity)
   -- first make sure we haven't already chosen an entity
   -- TODO: reconsider? maybe the new one is higher priority
   if self._selected_entity and self._selected_entity:is_valid() then
      return
   end

   self._selected_entity = nil
   
   -- consider whether we can actually use it
   local periodic_interaction = entity:get_component('stonehearth_ace:periodic_interaction')
   if periodic_interaction and periodic_interaction:is_usable() and periodic_interaction:is_valid_potential_user(self._entity) then
      self._selected_entity = entity
      
      -- cancel any existing task and start up a new task to interact with this entity
      self:_destroy_task()
      self._task = task_group:create_task('stonehearth_ace:periodically_interact', {item = entity})
                                 :once()
                                 :start()

      local check_task_fn = function()
         if not self._entity or not self._entity:is_valid() then
            self:_destroy_task()
         end
      end

      self._retry_listener = radiant.events.listen(self._entity, 'stonehearth:ai:ended_main_ai_loop_iteration', check_task_fn)

      if not self._task:wait() then
         self:_destroy_task()
         if self._retry_listener then
            self._retry_listener:destroy()
            self._retry_listener = nil
         end
         return false
      end
      if self._retry_listener then
         self._retry_listener:destroy()
         self._retry_listener = nil
      end
      self:_destroy_task()
   end
end

function PeriodicInteractionOrchestrator:_destroy_task()
   if self._task then
      self._task:destroy()
      self._task = nil
   end
end

return PeriodicInteractionOrchestrator
