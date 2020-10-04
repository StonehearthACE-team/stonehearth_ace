local LootTable = require 'stonehearth.lib.loot_table.loot_table'
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local AceDonationEncounter = class()

function AceDonationEncounter:start(ctx, info)

   --Get the drop location
   assert(ctx.player_id, "We don't have a player_id for this player")
   local town = stonehearth.town:get_town(ctx.player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end

   --Get the drop items
   assert(info.loot_table)
   local spawned_entities
   if info.container then
      spawned_entities = radiant.values(radiant.entities.spawn_items({ [info.container] = 1 }, drop_origin, 1, 3, { owner = ctx.player_id }))
      spawned_entities[1]:add_component('stonehearth:commands'):add_command('stonehearth:commands:open_loot')
      spawned_entities[1]:add_component('stonehearth:loot_drops'):set_loot_table(info.loot_table)
   else
      local town = stonehearth.town:get_town(ctx.player_id)
      local default_storage = town and town:get_default_storage()
      local spawned = radiant.entities.output_items(LootTable(info.loot_table):roll_loot(), drop_origin, 1, 3, { owner = ctx.player_id }, nil, default_storage, true)
      
      local inventory = stonehearth.inventory:get_inventory(ctx.player_id)
      for _, item in pairs(spawned.spilled) do
         inventory:add_item_if_not_full(item)
      end

      spawned_entities = radiant.entities.get_successfully_output_items(spawned)
   end
   
   if info.ctx_entity_registration_path then
      game_master_lib.register_entities(ctx, info.ctx_entity_registration_path, spawned_entities)
   end

   ctx.arc:trigger_next_encounter(ctx)
end

return AceDonationEncounter
