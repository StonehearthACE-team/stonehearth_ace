-- patching this only to automatically add our own item trackers
local Inventory = require 'stonehearth.services.server.inventory.inventory'
local AceInventory = class()

AceInventory._ace_old__pre_activate = Inventory._pre_activate
function AceInventory:_pre_activate()
   self:_ace_old__pre_activate()

   self:_add_more_trackers()
end

function AceInventory:_add_more_trackers()
   -- load up a json file to see what other trackers need to be added
   local trackers = radiant.resources.load_json('stonehearth_ace:data:inventory_trackers')

   for tracker, load in pairs(trackers) do
      if load then
         self:add_item_tracker(tracker)
      end
   end
end

AceInventory._ace_old_set_storage_filter = Inventory.set_storage_filter
function AceInventory:set_storage_filter(storage_entity, filter)
   local storage = storage_entity:get_component('stonehearth:storage')
   if not filter then
      filter = storage:get_limited_all_filter()
   end

   return self:_ace_old_set_storage_filter(storage_entity, filter)
end

return AceInventory