--[[
   as long as the player's inventory has at least the amount of gold coins needed,
   go to the closest gold coins entity, then extract the desired amount of gold coins into a new item and pick up that item
]]

local Entity = _radiant.om.Entity
local GOLD_URI = 'stonehearth:loot:gold'

local PickupGoldCoins = radiant.class()

PickupGoldCoins.name = 'pickup item with uri'
PickupGoldCoins.does = 'stonehearth_ace:pickup_gold_coins'
PickupGoldCoins.args = {
   amount = 'number',      -- the number of stacks of gold to pick up
}
PickupGoldCoins.priority = 0

function PickupGoldCoins:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)
   local is_owned_by_another_player = radiant.entities.is_owned_by_another_player

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth:pickup_gold_coins', player_id, function (entity)
         if is_owned_by_another_player(entity, player_id) then
            -- player does not own this item
            return false
         end

         return entity:get_uri() == GOLD_URI
      end)

   ai:set_think_output({
         filter_fn = filter_fn,
         description = GOLD_URI,
         owner_player_id = player_id,
      })
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupGoldCoins)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.PREV.filter_fn,
            description = ai.PREV.description,
            owner_player_id = ai.PREV.owner_player_id,
         })
         :execute('stonehearth_ace:pickup_gold_coins_adjacent', {
            source = ai.PREV.destination_entity,
            amount = ai.ARGS.amount,
            owner_player_id = ai.BACK(2).owner_player_id,
         })
