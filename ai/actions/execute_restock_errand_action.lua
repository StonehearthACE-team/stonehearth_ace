local ExecuteRestockErrand = radiant.class()

ExecuteRestockErrand.name = 'execute restock errand'
ExecuteRestockErrand.does = 'stonehearth:execute_restock_errand'
ExecuteRestockErrand.status_text_key = 'stonehearth:ai.actions.status_text.restock'
ExecuteRestockErrand.args = {
   type_id = 'string',
}
ExecuteRestockErrand.priority = {0, 1}

local _no_fill_backpack_predicate = function() return true end

local function make_fill_backpack_predicate(player_id, bin)
   if not radiant.entities.exists(bin) then
      return _no_fill_backpack_predicate
   end

   local storage = bin:get_component('stonehearth:storage')
   if storage:get_type() == 'input_crate' then
      local content_valid_function = storage:get_filter_function()
      local inventory = stonehearth.inventory:get_inventory(player_id)
      local exists = radiant.entities.exists
      local priority = storage:get_input_bin_priority()
      return stonehearth.ai:filter_from_key('item_for_input_bin', player_id .. ';' .. priority .. ';' .. storage:get_filter_key(), function(item)
         if not exists(item) then  -- TODO: Why is this even happening?
            return false
         end

         local source = inventory:container_for(item)
         if source then
            local source_storage = source:get_component('stonehearth:storage')
            if source_storage:get_type() == 'input_crate' and source_storage:get_input_bin_priority() >= priority then
               -- if the filter was changed/removed, we do want to move its items to other input bins
               if source_storage:passes(item) then
                  return false
               end
            end
         end

         return content_valid_function(item)
      end)
   end

   return _no_fill_backpack_predicate
end

function ExecuteRestockErrand:start_thinking(ai, entity, args)
   if not radiant.entities.exists_in_world(entity) then
      return  -- Entity not in world (e.g. suspended).
   end
   
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local inventory = stonehearth.inventory:get_inventory(work_player_id)
   if not inventory then
      ai:set_debug_progress('dead; no inventory for player ' .. (work_player_id or '<nil>'))
      return
   end
   local restock_director = inventory:get_restock_director(args.type_id)
   if not restock_director then
      ai:set_debug_progress('dead; no restock director')
      return
   end
   
   if not self:_try_take_errand(ai, entity, restock_director, work_player_id) then
      ai:set_debug_progress('waiting for an errand')
      self._errand_created_listener = radiant.events.listen(restock_director, 'stonehearth:restock:errand_available', function(errand_id)
            if self._errand_created_listener then  -- Only if we are still listening.
               -- Ideally we would only try the new errand, but that fails because fresh errands may
               -- not be valid for this entity, while old errands have become valid, and we don't want
               -- to miss out on those.
               if self:_try_take_errand(ai, entity, restock_director, work_player_id) then
                  return radiant.events.UNLISTEN
               end
            end
         end)
   end
end

function ExecuteRestockErrand:_try_take_errand(ai, entity, restock_director, work_player_id, maybe_errand_id)
   local errand_id, errand, score = restock_director:take_errand_to_consider(entity, maybe_errand_id)
   if not errand_id then
      return false
   end
   
   self._started = false
   self._restock_director = restock_director
   self._errand_id = errand_id
   
   if self._errand_created_listener then
      self._errand_created_listener:destroy()
      self._errand_created_listener = nil
   end
   
   self._errand_canceled_reject_listener = radiant.events.listen(restock_director, 'stonehearth:restock:errand_canceled', function(errand_id)
         if self._errand_id == errand_id then
            ai:reject()
         end
      end)
   self._errand_started_reject_listener = radiant.events.listen(restock_director, 'stonehearth:restock:errand_started', function(errand_id, starting_entity)
         if self._errand_id == errand_id and starting_entity ~= entity then
            -- Someone else successfully started it.
            ai:reject()
         end
      end)
   
   -- Errands fail if they are valid but thinking doesn't finish in some time.
   -- Ideally, this would never happen, but this should catch unexpected issues with reachability or races.
   self._errand_timeout_timer = stonehearth.calendar:set_timer('errand consider timeout', stonehearth.constants.inventory.restock_director.MAX_CONSIDER_DURATION_MS, function()
         restock_director:mark_errand_failed(errand_id)  -- The ensuing cancel event will cause a reject().
      end)

   ai:set_utility(score)
   ai:set_think_output({
      errand_id = errand_id,
      restock_director = restock_director,
      filter_fn = errand.filter_fn,
      storage = errand.storage,
      main_item = errand.main_item,
      extra_items = errand.extra_items,
      owner_player_id = work_player_id,
      fill_backpack_filter_fn = make_fill_backpack_predicate(work_player_id, errand.storage),
   })
   
   ai:set_debug_progress('executing errand ' .. errand_id)

   return true
end

function ExecuteRestockErrand:start(ai, entity, args)
   if not self._restock_director:try_start_errand(entity, self._errand_id) then
      ai:abort('errand already taken')  -- Someone else got it.
   end
   self._errand_canceled_abort_listener = radiant.events.listen(self._restock_director, 'stonehearth:restock:errand_canceled', function(errand_id)
         if self._errand_id == errand_id then
            ai:abort('errand canceled')
         end
      end)
   self._started = true
end

function ExecuteRestockErrand:stop_thinking(ai, entity, args)
   if not self._started and self._errand_id then
      self._restock_director:give_up_on_errand(entity, self._errand_id)
   end
   if self._errand_created_listener then
      self._errand_created_listener:destroy()
      self._errand_created_listener = nil
   end
   if self._errand_canceled_reject_listener then
      self._errand_canceled_reject_listener:destroy()
      self._errand_canceled_reject_listener = nil
   end
   if self._errand_started_reject_listener then
      self._errand_started_reject_listener:destroy()
      self._errand_started_reject_listener = nil
   end
   if self._errand_timeout_timer then
      self._errand_timeout_timer:destroy()
      self._errand_timeout_timer = nil
   end
end

function ExecuteRestockErrand:stop(ai, entity, args)
   if self._started and self._errand_id then
      self._restock_director:give_up_on_errand(entity, self._errand_id)
   end
   self._started = false
   self._restock_director = nil
   self._errand_id = nil
   if self._errand_canceled_abort_listener then
      self._errand_canceled_abort_listener:destroy()
      self._errand_canceled_abort_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(ExecuteRestockErrand)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:drop_backpack_contents_on_ground')
         :execute('stonehearth:pickup_item_into_backpack', {
            item = ai.BACK(4).main_item,
            owner_player_id = ai.BACK(4).owner_player_id,
            is_restocking = true,
         })
         :execute('stonehearth:fill_backpack_from_items', {
            candidates = ai.BACK(5).extra_items,
            range = 32,
            storage = ai.BACK(5).storage,
            owner_player_id = ai.BACK(5).owner_player_id,
            reserve_space = false,
            filter_fn = ai.BACK(5).fill_backpack_filter_fn,
            is_restocking = true,
         })
         :execute('stonehearth:fill_storage_from_backpack', {
            filter_fn = ai.BACK(6).filter_fn,
            storage = ai.BACK(6).storage,
            owner_player_id = ai.BACK(6).owner_player_id,
            ignore_missing = true,
         })
         :execute('stonehearth:call_method', {
            obj = ai.BACK(7).restock_director,
            method = 'finish_errand',
            args = { ai.ENTITY, ai.BACK(7).errand_id }
         })
