--[[
   changed to not track items in consumer containers or quest storage
]]

local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AceSellableItemTracker = class()

function AceSellableItemTracker:create_key_for_entity(entity, storage)
   assert(entity:is_valid(), 'entity is not valid.')

   local entity_uri, _ = entity_forms.get_uris(entity)

   local sellable

   -- is it sellable?
   local net_worth = radiant.entities.get_entity_data(entity_uri, 'stonehearth:net_worth')
   if net_worth and net_worth.shop_info and (net_worth.shop_info.sellable or net_worth.shop_info.sellable_only_if_wanted) then
      sellable = true
   end

   --if it's sellable, AND it is public storage or escrow storage, then return the uri as the key
   if sellable and storage and not storage:get_component('stonehearth_ace:consumer') then
      local storage_component = storage:get_component('stonehearth:storage')
      if storage_component and storage_component:allow_item_removal() and
            (storage_component:is_public() or storage_component:get_type() == 'escrow') then
         return entity_uri
      end
   end

   -- otherwise, nope!
   return nil

end

return AceSellableItemTracker
