local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local ReturningTrader = require 'stonehearth.services.server.game_master.controllers.script_encounters.returning_trader_script'
local AceReturningTrader = class()

local log = radiant.log.create_logger('returning_trader_script')

AceReturningTrader._ace_old_destroy = ReturningTrader.__user_destroy
function AceReturningTrader:destroy()
   self:_ace_old_destroy()
   self:_destroy_quest_storage()
end

function AceReturningTrader:_destroy_quest_storage()
   if self._sv._quest_storage then
      self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(false)
      self._sv._quest_storage = nil
   end
end

function AceReturningTrader:get_out_edge()
   log:debug('getting out_edge (%s)', tostring(self._sv.resolved_out_edge))
   return self._sv.resolved_out_edge
end

AceReturningTrader._ace_old__on_accepted = ReturningTrader._on_accepted
function AceReturningTrader:_on_accepted()
   self:_ace_old__on_accepted()

   local town = stonehearth.town:get_town(self._sv._player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end

   local quest_storage = radiant.entities.create_entity('stonehearth_ace:containers:quest', {owner = self._sv._player_id})
   local location, valid = radiant.terrain.find_placement_point(drop_origin, 4, 7, quest_storage)
   if not valid then
      radiant.entities.destroy_entity(quest_storage)
      return
   end

   -- create a quest storage near the town banner for these items
   local qs_comp = quest_storage:add_component('stonehearth_ace:quest_storage')
   qs_comp:set_requirements({{
      uri = self._sv._trade_data.want_uri,
      quantity = self._sv._trade_data.want_count,
   }})
   qs_comp:set_bulletin(self._sv._bulletin)
   radiant.terrain.place_entity_at_exact_location(quest_storage, location, {force_iconic = false})
   radiant.effects.run_effect(quest_storage, 'stonehearth:effects:gib_effect')

   self._sv._quest_storage = quest_storage
end

AceReturningTrader._ace_old__on_declined = ReturningTrader._on_declined
function AceReturningTrader:_on_declined()
   self._encounter_abandoned = true
   self:_destroy_quest_storage()
   self:_ace_old__on_declined()
end

AceReturningTrader._ace_old__on_success_accepted = ReturningTrader._on_success_accepted
function AceReturningTrader:_on_success_accepted()
   self._encounter_succeeded = true
   self:_ace_old__on_success_accepted()
end

function AceReturningTrader:_destroy_node()
   local out_edge
   if self._encounter_abandoned then
      out_edge = self._sv._trade_info.abandon_out_edge
   elseif self._encounter_succeeded then
      out_edge = self._sv._trade_info.success_out_edge
      --out_edge = self._sv.ctx.encounter:get_info().out_edge
   else
      out_edge = self._sv._trade_info.timeout_out_edge
   end

   log:debug('destroying node, progressing to out_edge: %s', tostring(out_edge))

   if out_edge then
      self._sv.resolved_out_edge = out_edge
      self._sv.ctx.arc:trigger_next_encounter(self._sv.ctx)
      self.__saved_variables:mark_changed()
   else
      self:destroy()
      assert(self._sv.ctx, 'No ctx saved in returning trader ecnounter script!')
      game_master_lib.destroy_node(self._sv.ctx.encounter, self._sv.ctx.parent_node)
   end
end

--- Given inventory data for a type of item, reserve N of those items
-- ACE: prioritize reserving from quest storage
function ReturningTrader:_reserve_items(inventory_data_for_item, num_desired)
   local num_reserved = 0
   local reserved = {}
   if self._sv._quest_storage then
      local storages = self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):get_storage_components()
      -- for returning trader, there's only a single requirement and a single storage
      if #storages > 0 then
         for id, item in pairs(storages[1]:get_items()) do
            if self:_try_reserving_item(reserved, id, item) then
               reserved[id] = true
               num_reserved = num_reserved + 1
               if num_reserved >= num_desired then
                  return true
               end
            end
         end
      end
   end

   for id, item in pairs(inventory_data_for_item.items) do
      if not reserved[id] and self:_try_reserving_item(reserved, id, item) then
         num_reserved = num_reserved + 1
         if num_reserved >= num_desired then
            return true
         end
      end
   end
   --if we got here, we didn't reserve enough to satisfy demand.
   self:_unreserve_items()
   return false
end

function AceReturningTrader:_try_reserving_item(reserved, id, item)
   if item and not reserved[id] then
      local leased = stonehearth.ai:acquire_ai_lease(item, self._sv.trader_entity)
      if leased then
         table.insert(self._sv.leased_items, item)
         return true
      end
   end
end

function AceReturningTrader:_accept_trade()
   if self._sv._quest_storage then
      -- make sure they don't bring more items here since we have all we need
      self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):set_enabled(false)
   end
   --TODO: go through the reserved items and nuke them all
   self:_take_items()

   --Add the new items to the space near the banner
   local town = stonehearth.town:get_town(self._sv._player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end

   --If the reward type was an object, make the new objects
   if self._sv._trade_info.rewards[self._sv._trade_data.reward_uri].type == 'object' then
      local uris = {}
      uris[self._sv._trade_data.reward_uri] = self._sv._trade_data.reward_count
      --TODO: attach a brief particle effect to the new stuff
      
      local town = stonehearth.town:get_town(self._sv._player_id)
      local default_storage = town and town:get_default_storage()
      local options = {
         owner = self._sv._player_id,
         add_spilled_to_inventory = true,
         inputs = default_storage,
         spill_fail_items = true,
         require_matching_filter_override = true,
      }
      radiant.entities.output_items(uris, drop_origin, 1, 3, options)
   end
end

return AceReturningTrader
