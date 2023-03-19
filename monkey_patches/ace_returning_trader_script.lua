local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
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

   local use_quest_storage = self._sv._trade_info.use_quest_storage ~= false
   if stonehearth.client_state:get_client_gameplay_setting(self._sv._player_id, 'stonehearth_ace', 'use_quest_storage', true) and use_quest_storage then
      local item_requirements = {{
         uri = self._sv._trade_data.want_uri,
         quantity = self._sv._trade_data.want_count,
      }}
      self._sv._quest_storage = game_master_lib.create_quest_storage(self._sv._player_id, self._sv._trade_info.quest_storage_uri, item_requirements, self._sv._bulletin)
   end
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

--- Returns the URI of the desired item, and the number of desired items
function AceReturningTrader:_get_desired_items()
   local inventory = stonehearth.inventory:get_inventory(self._sv._player_id)
   local jobs_controller = stonehearth.job:get_jobs_controller(self._sv._player_id)

   local available = WeightedSet(rng)
   local fallback, fallback2 = {}, {}

   for uri, wanted_item in pairs(self._sv._trade_info.wants) do
      local min, max = wanted_item.min, wanted_item.max
      local data = radiant.entities.get_component_data(uri, 'stonehearth:entity_forms')
      local item_real_uri = data and data.iconic_form or uri

      local inventory_data_for_item = inventory:get_items_of_type(item_real_uri)
      
      -- try to find an owned item where the amount is less than the max possible items requested
      -- or an unowned craftable item where we have at least one of each ingredient
      -- otherwise, set fallback item to an item not in our inventory and ask for the min amount
      -- otherwise, set fallback item to an item that *is* in our inventory, but use max amount
      if (inventory_data_for_item and inventory_data_for_item.count < max) or
            (not inventory_data_for_item and self:_is_item_craftable(inventory, jobs_controller, uri)) then
         local proposed_number = math.max((inventory_data_for_item and inventory_data_for_item.count + 1) or 1, rng:get_int(min, max - 1))
         available:add({uri, proposed_number}, wanted_item.weight or 1)
      elseif not inventory_data_for_item then
         table.insert(fallback, {uri, min})
      elseif inventory_data_for_item.count >= max then
         table.insert(fallback2, {uri, max})
      end
   end

   if not available:is_empty() then
      return unpack(available:choose_random())
   elseif next(fallback) then
      -- don't get picky, just choose one
      return unpack(fallback[rng:get_int(1, #fallback)])
   elseif next(fallback2) then
      -- don't get picky, just choose one
      return unpack(fallback2[rng:get_int(1, #fallback2)])
   else
      -- really? *none* of the listed items fit the bill? is that possible? just randomly select one then
      local item_uri = self._sv._want_table[rng:get_int(1, #self._sv._want_table)]
      return item_uri, self._sv._trade_info.wants[item_uri].min
   end
end

function AceReturningTrader:_is_item_craftable(inventory, jobs_controller, uri)
   local craftable = jobs_controller:get_craftable_recipes_for_product(uri)

   -- check each ingredient to see if we have any in our inventory
   for _, recipe_info in ipairs(craftable) do
      local is_craftable = true
      for _, ingredient in ipairs(recipe_info.recipe.ingredients) do
         if inventory:get_amount_in_storage(ingredient.uri, ingredient.material) < 1 then
            is_craftable = false
            break
         end
      end

      if is_craftable then
         return true
      end
   end

   return false
end

--- Given inventory data for a type of item, reserve N of those items
-- ACE: prioritize reserving from quest storage
function AceReturningTrader:_reserve_items(inventory_data_for_item, num_desired)
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

function AceReturningTrader:_get_item_resale_value(item)
   -- don't worry about cunning town bonus here, or who's "selling" to whom, just use the raw value
   return radiant.entities.get_net_worth(entity_forms.get_root_entity(item) or item) or 0
end

--TODO: instead of doing this, the trader should pick them up and haul them off
function AceReturningTrader:_take_items()
   -- ACE: calculate total value of items so trade gold earned/spent can be adjusted
   local total_gold = 0
   for i, item in ipairs(self._sv.leased_items) do
      total_gold = total_gold + self:_get_item_resale_value(item)
      stonehearth.ai:release_ai_lease(item, self._sv.caravan_entity)
      radiant.entities.kill_entity(item)
   end
   self._sv.leased_items = {}

   -- "earned" because we "sold" these items
   stonehearth.inventory:get_inventory(self._sv._player_id):add_trade_gold_earned(total_gold)
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
      local items = radiant.entities.output_items(uris, drop_origin, 1, 3, options)
      -- ACE: calculate total value of items so trade gold earned/spent can be adjusted
      local total_gold = 0
      for _, item in pairs(items.succeeded) do
         total_gold = total_gold + self:_get_item_resale_value(item)
      end
      for _, item in pairs(items.spilled) do
         total_gold = total_gold + self:_get_item_resale_value(item)
      end

      -- "spent" because we "bought" these items
      stonehearth.inventory:get_inventory(self._sv._player_id):add_trade_gold_spent(total_gold)
   end
end

return AceReturningTrader
