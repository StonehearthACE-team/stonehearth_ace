local DropCarryingInStorageAdjacent = require 'stonehearth.ai.actions.drop_carrying_in_storage_adjacent_action'
local AceDropCarryingInStorageAdjacent = radiant.class()

local GOLD_URI = 'stonehearth:loot:gold'
local log = radiant.log.create_logger('drop_carrying_in_storage_adjacent')

DropCarryingInStorageAdjacent.args.ignore_missing = {
   type = 'boolean',
   default = false,
}

function AceDropCarryingInStorageAdjacent:run(ai, entity, args)
   radiant.check.is_entity(entity)

   if not radiant.entities.get_carrying(entity) then
      if not args.ignore_missing then
         ai:abort('cannot put carrying in storage if you are not carrying anything')
      end
      return
   end

   local sc = args.storage:add_component('stonehearth:storage')
   if sc:is_full() then
      return
   end

   if not radiant.entities.is_adjacent_to(entity, args.storage) then
      ai:abort(string.format('%s is not adjacent to %s', tostring(entity), tostring(args.storage)))
   end

   radiant.entities.turn_to_face(entity, args.storage)
   local storage_location = radiant.entities.get_world_grid_location(args.storage)
   ai:execute('stonehearth:run_putdown_effect', { location = storage_location })

   if sc:is_full() then
      -- Have to check again if the storage is full because it might have become full while we were running the
      -- put down effect.
      return
   end

   local item = radiant.entities.remove_carrying(entity)
   -- note that the item might have been destroyed during the putdown effect (in one case the food rotted away)
   if item then
      -- remove our lease on this item, if we have one
      stonehearth.ai:release_ai_lease(item, entity)
      ai:unprotect_argument(item)

      -- if it's gold, add the amount of stacks to the inventory (and specify this storage entity) and destroy the original item
      if sc:add_gold_item(item) == false then
         sc:add_item(item)
      end
   end
end

return AceDropCarryingInStorageAdjacent
