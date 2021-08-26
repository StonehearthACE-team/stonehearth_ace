local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local ReturningTrader = require 'stonehearth.services.server.game_master.controllers.script_encounters.returning_trader_script'
local AceReturningTrader = class()

local log = radiant.log.create_logger('returning_trader_script')

function AceReturningTrader:get_out_edge()
   log:debug('getting out_edge (%s)', tostring(self._sv.resolved_out_edge))
   return self._sv.resolved_out_edge
end

AceReturningTrader._ace_old__on_declined = ReturningTrader._on_declined
function AceReturningTrader:_on_declined()
   self._encounter_abandoned = true
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

function AceReturningTrader:_accept_trade()
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
         owner = self._sv.player_id,
         add_spilled_to_inventory = true,
         inputs = default_storage,
         spill_fail_items = true,
         require_matching_filter_override = true,
      }
      radiant.entities.output_items(uris, drop_origin, 1, 3, options)
   end
end

return AceReturningTrader
