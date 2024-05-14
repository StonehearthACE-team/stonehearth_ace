local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local BuildItemTypeOnStructure = radiant.class()

BuildItemTypeOnStructure.name = 'build an item type'
BuildItemTypeOnStructure.does = 'stonehearth_ace:build_item_type_on_structure'
BuildItemTypeOnStructure.args = {}
BuildItemTypeOnStructure.priority = {0, 1}

local FAILSAFE_TIMEOUT = 5000
local RESTART_TIMEOUT = 2000

local function _is_placeable_iconic(player_id, iconic_uri, quality, require_exact, item)
   if not item or not item:is_valid() then
      return false
   end
   local root_form = entity_forms.get_root_entity(item)
   if not root_form then
      return false
   end
   local item_uri = item:get_uri()
   if item_uri ~= iconic_uri then
      if require_exact then
         return false
      end

      -- if not requiring the exact uri, check for alternates
      local alternates = radiant.entities.get_alternate_uris(iconic_uri)
      local found_alternate
      if alternates then
         for uri, _ in pairs(alternates) do
            if item_uri == uri then
               found_alternate = true
               break
            end
         end
      end
      if not found_alternate then
         return false
      end
   end
   if quality ~= -1 and radiant.entities.get_item_quality(entity_forms.get_root_entity(item) or item) ~= quality then
      return false
   end
   if player_id ~= item:get_player_id() then
      return false
   end
   local being_placed = root_form:get_component('stonehearth:entity_forms'):is_being_placed()
   if being_placed then
      return false
   end

   local placement_data = radiant.entities.get_entity_data(root_form, 'stonehearth:placement')
   if placement_data and placement_data.tag then  -- requires special placement action (e.g. summon_stone)
      return false
   end

   return true
end

local function _is_ghost_for_iconic(player_id, iconic_uri, quality, require_exact, possible_ghost)
   if not possible_ghost or not possible_ghost:is_valid() then
      return false
   end

   if possible_ghost:get_player_id() ~= player_id then
      return false
   end

   local ghost_form_component = possible_ghost:get_component('stonehearth:ghost_form')
   if not ghost_form_component or not ghost_form_component:is_building_fixture() then
      return false
   end

   local ghost_iconic_uri = ghost_form_component:get_iconic_uri()
   if ghost_iconic_uri ~= iconic_uri then
      if require_exact then
         return false
      end

      -- if not requiring the exact uri, check for alternates
      local alternates = radiant.entities.get_alternate_uris(iconic_uri)
      local found_alternate
      if alternates then
         for uri, _ in pairs(alternates) do
            if ghost_iconic_uri == uri then
               found_alternate = true
               break
            end
         end
      end
      if not found_alternate then
         return false
      end
   end

   local requested_quality = ghost_form_component:get_requested_quality()
   if quality == -1 then
      -- We picked a random object...
      if requested_quality ~= nil then
         return false  -- ...but we wanted a specific quality.
      end
   else
      -- We picked an object of a specific quality...
      if requested_quality ~= quality then
         return false  -- ...but not the quality that this ghost wants.
      end
   end

   if not ghost_form_component:is_place_item_type() then
      return false
   end

   return true
end

function BuildItemTypeOnStructure:_try_next_entry(ai, entity)
   local work_player_id = radiant.entities.get_work_player_id(self._entity)
   local town = stonehearth.town:get_town(work_player_id)
   local item_types = town:get_requested_build_placement_tasks()
   local entry

   local prev_key = item_types[self._item_type_cursor] and self._item_type_cursor or nil
   self._item_type_cursor, entry = next(item_types, prev_key)

   if not self._item_type_cursor then
      -- We've run through the entire list of items to place.  Take a breath, then start again.
      self._restart_timer = radiant.set_realtime_timer('place_item_type_2 restart', RESTART_TIMEOUT, function()
         self._restart_timer:destroy()
         self._restart_timer = nil
         self:_try_next_entry(ai, entity)
      end)

      return
   end

   -- Okay, try this one!
   local iconic_uri = entry.iconic_uri
   local quality = entry.quality
   local require_exact = entry.require_exact
   local require_exact_str = require_exact and '*' or ''

   local pickup_filter = stonehearth.ai:filter_from_key('stonehearth:place_item_type_on_structure',
         work_player_id .. '+q:' .. quality .. ':' .. iconic_uri .. require_exact_str .. ':p',
         function(item)
            return _is_placeable_iconic(work_player_id, iconic_uri, quality, require_exact, item)
         end)

   local ghost_filter = stonehearth.ai:filter_from_key('stonehearth_ace:build_item_type_on_structure',
         work_player_id .. '+q:' .. quality .. ':' .. iconic_uri .. require_exact_str .. ':g',
         function(ghost)
            return _is_ghost_for_iconic(work_player_id, iconic_uri, quality, require_exact, ghost)
         end)

   if quality ~= -1 or require_exact then
      ai:set_utility(1)  -- Always prioritize placing non-standard *or exact* items.
   end

   self._failsafe_timer = radiant.set_realtime_timer('place_item_type_2 failsafe', FAILSAFE_TIMEOUT, function()
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
      ai:clear_think_output()
      ai:reject('fail safe timeout hit')
   end)

   if self._restart_timer then
      self._restart_timer:destroy()
      self._restart_timer = nil
   end

   if self._items_changed_listener then
      self._items_changed_listener:destroy()
      self._items_changed_listener = nil
   end

   ai:set_think_output({
      iconic_filter = pickup_filter,
      ghost_filter = ghost_filter,
      owner_player_id = work_player_id,
   })
end

function BuildItemTypeOnStructure:_on_items_changed()
   if self._item_type_cursor then
      -- We aren't nil, and therefore aren't waiting for new stuff.
      return
   end

   self:_try_next_entry(self._ai, self._entity)
end

function BuildItemTypeOnStructure:start_thinking(ai, entity, args)
   self._entity = entity
   self._ai = ai

   local work_player_id = radiant.entities.get_work_player_id(self._entity)
   local town = stonehearth.town:get_town(work_player_id)
   self._items_changed_listener = radiant.events.listen(town, 'stonehearth_ace:town:build_item_types_changed', self, self._on_items_changed)


   -- THis would be a good place to put in a multi-tick sleep (randomized) so we don't loop incessantly.
   self:_try_next_entry(ai, entity)
end

function BuildItemTypeOnStructure:stop_thinking(ai, entity, args)
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end

   if self._restart_timer then
      self._restart_timer:destroy()
      self._restart_timer = nil
   end

   if self._items_changed_listener then
      self._items_changed_listener:destroy()
      self._items_changed_listener = nil
   end
end

function BuildItemTypeOnStructure:stop(ai, entity, args)
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end

   if self._restart_timer then
      self._restart_timer:destroy()
      self._restart_timer = nil
   end

   if self._items_changed_listener then
      self._items_changed_listener:destroy()
      self._items_changed_listener = nil
   end
end

function BuildItemTypeOnStructure:start(ai, entity, args)
   -- Huh?  This is nonsense.
   ai:set_status_text_key('stonehearth:ai.actions.status_text.place_item_on_structure', { target = ai.CURRENT.carrying })
end


local ai = stonehearth.ai
return ai:create_compound_action(BuildItemTypeOnStructure)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:build:work_player_id_changed',
         })
         :execute('stonehearth:find_reachable_entity_type_anywhere', {
               filter_fn = ai.BACK(2).iconic_filter,
               material = '__nonsense__',
               description = 'place_item_type_on_structure freta',
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
