local InventoryCheck = class()
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('inventory_check')

function InventoryCheck:start(ctx, info)
   local inventory = stonehearth.inventory:get_inventory(ctx.player_id)
   if not inventory then
      log:debug('no inventory found')
      return false
   end
   
   local threshold = nil

   if type(info.threshold) == "table" then
      threshold = rng:get_int(info.threshold.min, info.threshold.max)
   else
      threshold = info.threshold
   end

   local items = inventory:get_item_tracker('stonehearth:basic_inventory_tracker')
                              :get_tracking_data()
   local placeable_items = inventory:get_item_tracker('stonehearth:placeable_item_inventory_tracker')
                                          :get_tracking_data()
   local total_item_count = 0
   local all_matching_items = {}                           
   local check = info.check
   local uris = info.uris
   local materials = info.materials                           

   if uris then
      for _, uri in pairs(uris) do
         if items:contains(uri) then
            local matching_items = items:get(uri)
            total_item_count = total_item_count + matching_items.count
         end
         if placeable_items:contains(uri) then
            local matching_placeable_items = placeable_items:get(uri)
            total_item_count = total_item_count + matching_placeable_items.count
         end
      end
   elseif materials then
      local keys, placeable_keys = items:get_keys() and placeable_items:get_keys()
      for _, uri in pairs(keys) do
         local matching_items = items:get(uri)
         local _, entity = next(matching_items.items)
         if entity then
            local match = true
            for _, material in pairs(materials) do
               if not radiant.entities.is_material(entity, material) then
                  match = false
                  break
               end
            end           

            if match then
               all_matching_items[uri] = matching_items
               total_item_count = total_item_count + matching_items.count
            end
         end
      end
      for _, uri in pairs(placeable_keys) do
         local matching_placeable_items = placeable_items:get(uri)
         local _, entity = next(matching_placeable_items.items)
         if entity then
            local match = true
            for _, material in pairs(materials) do
               if not radiant.entities.is_material(entity, material) then
                  match = false
                  break
               end
            end           

            if match then
               all_matching_items[uri] = matching_placeable_items
               total_item_count = total_item_count + matching_placeable_items.count
            end
         end
      end
   end

   if check == 'less_than' then
      return total_item_count < threshold
   elseif check == 'greater_than' then
      return total_item_count > threshold
   end

   return false
end

return InventoryCheck