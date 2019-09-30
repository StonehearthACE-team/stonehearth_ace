local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local PlaceSummonStoneTypeAction = radiant.class()

PlaceSummonStoneTypeAction.name = 'place summon stone (type)'
PlaceSummonStoneTypeAction.does = 'stonehearth:place_item_type_on_structure_2'
PlaceSummonStoneTypeAction.args = {
   iconic_uri = 'string',
   quality = 'number'  -- ignored
}
PlaceSummonStoneTypeAction.priority = {0, 1}

local FAILSAFE_TIMEOUT = 5000

local function _is_placeable_iconic(player_id, iconic_uri, item)
   if not item or not item:is_valid() then
      return false
   end
   if item:get_uri() ~= iconic_uri then
      return false
   end
   if player_id ~= radiant.entities.get_player_id(item) then
      return false
   end
   local root_form = entity_forms.get_root_entity(item)
   if not root_form then
      return false
   end
   local being_placed = root_form:get_component('stonehearth:entity_forms'):is_being_placed()
   if being_placed then
      return false
   end

   local placement_data = radiant.entities.get_entity_data(root_form, 'stonehearth:placement')
   if not (placement_data and placement_data.tag == 'summon_stone') then
      return false
   end
   
   return true
end

local function _is_ghost_for_iconic(player_id, iconic_uri, possible_ghost)
   if not possible_ghost or not possible_ghost:is_valid() then
      return false
   end

   if radiant.entities.get_player_id(possible_ghost) ~= player_id then
      return false
   end

   local ghost_form_component = possible_ghost:get_component('stonehearth:ghost_form')
   if not ghost_form_component then
      return false
   end

   if ghost_form_component:get_iconic_uri() ~= iconic_uri then
      return false
   end

   if not ghost_form_component:is_place_item_type() then
      return false
   end
   
   return true
end

function PlaceSummonStoneTypeAction:_try_next_entry(ai, entity)
   local work_player_id = radiant.entities.get_work_player_id(self._entity)
   local town = stonehearth.town:get_town(work_player_id)
   local item_types = town:get_requested_placement_tasks()
   local entry

   self._item_type_cursor, entry = next(item_types, self._item_type_cursor)

   if not self._item_type_cursor then
      -- We might be at the end, ready to start again, so try once more.
      self._item_type_cursor, entry = next(item_types)
   end

   if not self._item_type_cursor then
      return
   end

   -- Okay, try this one!
   local iconic_uri = entry.iconic_uri
   local quality = entry.quality

   local pickup_filter = stonehearth.ai:filter_from_key('stonehearth:place_summon_stone_type_on_structure', work_player_id .. ':' .. iconic_uri .. ':p', function(item)
         return _is_placeable_iconic(work_player_id, iconic_uri, item)
      end)
   
   local ghost_filter = stonehearth.ai:filter_from_key('stonehearth:place_summon_stone_type_on_structure', work_player_id .. ':' .. iconic_uri .. ':g', function(ghost)
         return _is_ghost_for_iconic(work_player_id, iconic_uri, ghost)
      end)

   if quality ~= -1 then
      self._is_priority = true
      --ai:set_utility(1)  -- Always prioritize placing non-standard items.
   else
      self._is_priority = false
   end

   self._failsafe_timer = radiant.set_realtime_timer('place_item_type_2 failsafe', FAILSAFE_TIMEOUT, function()
      ai:clear_think_output()
      ai:reject('fail safe timeout hit')
   end)

   ai:set_think_output({
      iconic_filter = pickup_filter,
      ghost_filter = ghost_filter,
      owner_player_id = work_player_id,
   })
end

function PlaceSummonStoneTypeAction:_on_items_changed()
   if self._item_type_cursor then
      -- We aren't nil, and therefore aren't waiting for new stuff.
      return
   end

   self:_try_next_entry(self._ai, self._entity)
end

function PlaceSummonStoneTypeAction:start_thinking(ai, entity, args)
   self._entity = entity
   self._ai = ai

   if not self._rejecting then
      self._item_type_cursor = nil
   end
   self._rejecting = false

   local work_player_id = radiant.entities.get_work_player_id(self._entity)
   local town = stonehearth.town:get_town(work_player_id)
   self._items_changed_listener = radiant.events.listen(town, 'stonehearth:town:place_item_types_changed', self, self._on_items_changed)


   -- THis would be a good place to put in a multi-tick sleep (randomized) so we don't loop incessantly.
   self:_try_next_entry(ai, entity)
end

function PlaceSummonStoneTypeAction:stop_thinking(ai, entity, args)
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end

   if self._items_changed_listener then
      self._items_changed_listener:destroy()
      self._items_changed_listener = nil
   end
end

function PlaceSummonStoneTypeAction:stop(ai, entity, args)
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end

   if self._items_changed_listener then
      self._items_changed_listener:destroy()
      self._items_changed_listener = nil
   end
end

function PlaceSummonStoneTypeAction:start(ai, entity, args)
   -- Huh?  This is nonsense.
   ai:set_status_text_key('stonehearth:ai.actions.status_text.place_item_on_structure', { target = ai.CURRENT.carrying })
end

function PlaceSummonStoneTypeAction:on_reject(ai, entity, args)
   self._rejecting = true
end

function PlaceSummonStoneTypeAction:compose_utility(entity, self_utility, child_utilities, current_activity)
   if self._is_priority then
      return 1
   else
      return child_utilities:get('stonehearth:pickup_item_type') * 0.8
         + child_utilities:get('stonehearth:goto_entity_type') * 0.2
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PlaceSummonStoneTypeAction)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:find_reachable_entity_type_anywhere', {
               filter_fn = ai.BACK(2).iconic_filter,
               material = '__nonsense__',
               description = 'place_item_type_on_structure',
            })
         :execute('stonehearth:pickup_item_type', {
               filter_fn = ai.BACK(3).iconic_filter,
               description = 'pickup placeable iconic for ghost',
               owner_player_id = ai.BACK(3).owner_player_id,
            })
         :execute('stonehearth:goto_entity_type', {
               filter_fn = ai.BACK(4).ghost_filter,
               description = 'find ghost for iconic',
             })
         :execute('stonehearth:reserve_entity', {
               entity = ai.PREV.destination_entity,
            })
         :execute('stonehearth:place_carrying_on_structure_adjacent', {
               ghost = ai.BACK(2).destination_entity,
            })
