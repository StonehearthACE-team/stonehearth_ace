local validator = radiant.validator
local AceShopService = class()

function AceShopService:trigger_trader_encounter_command(session, response, shop_entity)
   validator.expect_argument_types({'Entity'}, shop_entity)
   local shop_component = shop_entity:get_component('stonehearth_ace:market_stall') or shop_entity:get_component('stonehearth:shop_trigger')
   if shop_component then
      shop_component:trigger_trader_encounter()
   end
end

function AceShopService:_item_in_material_filter(entity_description, filter)
   if not filter.material and not filter.exclude_material then
      return true
   end

   --Record all the materials for this entity
   local materials = {}
   local tags = entity_description.materials or {}
   if radiant.util.is_string(tags) then
      tags = radiant.util.split_string(tags)
   end
   for _, tag in ipairs(tags) do
      materials[tag] = true
   end

   -- ACE addition: exclusion filters
   if filter.exclude_material then
      for _, exclude_material in ipairs(filter.exclude_material) do
         -- split this material and check each individual tag
         -- ALL individual tags for this material must match to exclude
         local exclude_tags = radiant.util.split_string(exclude_material)
         local exclude = false
         for _, tag in ipairs(exclude_tags) do
            if not materials[tag] then
               exclude = true
               break
            end
         end
         if exclude then
            return false
         end
      end
   end

   --for each material in the filter, check if the entity has it
   --the entity must match all the items in the filter, or it will fail the filter
   if filter.material then
      for _, material in ipairs(filter.material) do
         local tags = radiant.util.split_string(material)
         for _, tag in ipairs(tags) do
            if not materials[tag] then
               return false
            end
         end
      end
   end

   return true
end

return AceShopService
