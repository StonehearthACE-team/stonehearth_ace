local AceInventoryService = class()

function AceInventoryService:destroy()
   if self._item_quality_added_listener then
      self._item_quality_added_listener:destroy()
      self._item_quality_added_listener = nil
   end
   if self._item_quality_removed_listener then
      self._item_quality_removed_listener:destroy()
      self._item_quality_removed_listener = nil
   end
   if self._reconsider_restock_listener then
      self._reconsider_restock_listener:destroy()
      self._reconsider_restock_listener = nil
   end
end

function AceInventoryService:create_restock_cache_listeners()
   -- this is set up by the inventory service, but the cache at this level is never used so this interval is unnecessary
   -- clearing it here means we don't have to patch in the old destroy function, we can just override it
   if self._restock_cache_clear_interval then
      self._restock_cache_clear_interval:destroy()
      self._restock_cache_clear_interval = nil
   end

   local normal_quality = stonehearth.constants.item_quality.NORMAL

   self._item_quality_added_listener = radiant.events.listen(stonehearth, 'stonehearth:item_quality_added', function(args)
         -- only bother with item qualities higher than normal
         if args.item_quality > normal_quality then
            local inventory = self:get_inventory(args.entity)
            if inventory then
               inventory:set_restock_item_quality(args.entity:get_id(), args.item_quality)
            end
         end
      end)

   self._item_quality_removed_listener = radiant.events.listen(stonehearth, 'stonehearth_ace:item_quality_removed', function(args)
         local inventory = self:get_inventory(args.player_id)
         if inventory then
            inventory:set_restock_item_quality(args.entity_id)
         end
      end)

   self._reconsider_restock_listener = radiant.events.listen(stonehearth, 'stonehearth_ace:reconsider_restock', function(args)
         local inventory = self:get_inventory(args.player_id)
         if inventory then
            inventory:set_restock_should_restock(args.entity_id, args.should_restock or nil)
         end
      end)
end

return AceInventoryService
