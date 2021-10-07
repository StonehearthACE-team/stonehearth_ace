local PickupItemTypeFromBackpack = require 'stonehearth.ai.actions.pickup_item_type_from_backpack_action'
local AcePickupItemTypeFromBackpack = class()

PickupItemTypeFromBackpack.args.ignore_missing = {
   type = 'boolean',
   default = false,
}

function AcePickupItemTypeFromBackpack:run(ai, entity, args)
   -- first check if we actually have the item in our storage; if not, ignore the action
   -- because apparently we can't interact with ai.CURRENT once the action is already running!
   if not self._item:is_valid() then
      ai:abort('item in backpack destroyed')
   end

   local owner_player_id = args.owner_player_id
   if args.keep_item_player_id then
      owner_player_id = self._item:get_player_id()
   end

   if stonehearth.ai:prepare_to_pickup_item(ai, entity, self._item, owner_player_id) then
      return
   end
   assert(not radiant.entities.get_carrying(entity))

   local storage_component = entity:get_component('stonehearth:storage')
   local item = storage_component:remove_item(self._item:get_id(), nil, owner_player_id)
   if not item then
      if args.ignore_missing then
         return
      else
         ai:abort('failed to pull item out of backpack')
      end
   end
   stonehearth.ai:pickup_item(ai, entity, self._item, nil, owner_player_id)
end

return AcePickupItemTypeFromBackpack
