local DonationDialogEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.donation_dialog_encounter'
local AceDonationDialogEncounter = class()
local rng = _radiant.math.get_default_rng()
local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

-- have to override to deal with different format of result from loot table
function AceDonationDialogEncounter:start(ctx, info)
   self._sv.player_id = ctx.player_id
   self._sv.ctx = ctx

   game_master_lib.compile_bulletin_nodes(info.nodes, ctx)
   self._sv._i18n_data = info.i18n_data

   --Get the drop items
   local reward_items = {}
   if info.loot_table then
      self._sv.items = LootTable(info.loot_table)
                        :roll_loot()
      for uri, detail in pairs(self._sv.items) do
         local display_name = nil
         local catalog_data = stonehearth.catalog:get_catalog_data(uri)
         if catalog_data then
            display_name = catalog_data.display_name
         end

         local count = 0
         for quality, quantity in pairs(detail) do
            count = count + quantity
         end
         table.insert(reward_items, {count = count, display_name = display_name })
      end
   else
      self._sv.items = {}
   end

   --If gold amount was specified in the json or from a previous encounter, add that as well
   local gold = info.donation_gold or ctx.donation_gold
   if gold then
      self._sv.gold = gold
      table.insert(reward_items, {count = gold, display_name = 'i18n(stonehearth:entities.loot.gold.label)'})
   end

   if info.choose_ctx_portrait then
      local chosen_portrait = nil
      if type(info.choose_ctx_portrait) == 'table' then
         chosen_portrait = portraits[rng:get_int(1, #info.choose_ctx_portrait)]
      end
      ctx.dialog_tree_ctx_portrait = chosen_portrait
   end

   if info.use_ctx_portrait and ctx.dialog_tree_ctx_portrait then
      local ctx_portrait = ctx.dialog_tree_ctx_portrait
      for _, node in pairs(info.nodes) do
         if node.bulletin.portrait then --only sub it in if there's a portrait defined
            node.bulletin.portrait = ctx_portrait
         end
      end
   end


   --Compose the bulletin
   local bulletin_data = info.nodes.simple_message.bulletin
   bulletin_data.demands = reward_items

   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
                                       :set_ui_view('StonehearthDialogTreeBulletinDialog')
                                       :set_callback_instance(self)
                                       :set_type('quest')
                                       :set_sticky(false)
                                       :set_keep_open(false)
                                       :set_close_on_handle(true)

   if(info.expiration_timeout) then
      self._sv.bulletin:set_active_duration(info.expiration_timeout)
      self._active_duration_listener = radiant.events.listen_once(self._sv.bulletin, 'stonehearth:bulletin:on_remove_bulletin_timer', self, self._destroy_bulletin)
   end

   if self._sv._i18n_data then
      for i18n_var_name, i18n_var_path in pairs(self._sv._i18n_data) do
         local i18n_var = ctx:get(i18n_var_path)
         if i18n_var then
            self._sv.bulletin:add_i18n_data(i18n_var_name, i18n_var)
         end
      end
   end

   self._sv.bulletin:set_data(bulletin_data)
   self.__saved_variables:mark_changed()
end

function AceDonationDialogEncounter:_acknowledge()
   local town = stonehearth.town:get_town(self._sv.player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end
   
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   local town = stonehearth.town:get_town(self._sv.player_id)
   local default_storage = town and town:get_default_storage()
   local options = {
      owner = self._sv.player_id,
      add_spilled_to_inventory = true,
      inputs = default_storage,
      spill_fail_items = true,
      require_matching_filter_override = true,
   }
   radiant.entities.output_items(self._sv.items, drop_origin, 1, 3, options)

   if self._sv.gold then
      inventory:add_gold(self._sv.gold)
   end
end

AceDonationDialogEncounter._ace_old_destroy = DonationDialogEncounter.destroy
function AceDonationDialogEncounter:destroy()
   if self._active_duration_listener then
      self._active_duration_listener:destroy()
      self._active_duration_listener = nil
   end

   self:_ace_old_destroy()
end

return AceDonationDialogEncounter
