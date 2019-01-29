local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local FarmingService = require 'stonehearth.services.server.farming.farming_service'
AceFarmingService = class()

-- TODO: modify this to add the other "growing preferences" and get rid of that whole call handler/system
--[[
--- Given a new crop type, record some important things about it
function FarmingService:get_crop_details(crop_type)
   local details = self._crop_details[crop_type]
   if not details then
      local catalog_data = stonehearth.catalog:get_catalog_data(crop_type)
      details = {}
      details.uri = crop_type
      details.name = catalog_data.display_name
      details.description = catalog_data.description
      details.icon = catalog_data.icon
      local json = radiant.resources.load_json(crop_type)
      if json and json.components and json.components['stonehearth:growing'] and json.components['stonehearth:growing'].preferred_seasons then
         local biome_uri = stonehearth.world_generation:get_biome_alias()
         local seasons = stonehearth.seasons:get_seasons()
         if biome_uri and seasons then  -- Hacky protection against races; should never happen in theory.
            local preferred_seasons = json.components['stonehearth:growing'].preferred_seasons[biome_uri]
            details.preferred_seasons = {}
            if preferred_seasons then
               for _, season_id in ipairs(preferred_seasons) do
                  if seasons[season_id] then
                     table.insert(details.preferred_seasons, seasons[season_id].display_name)
                  end
               end
            end
         end
      end
      self._crop_details[crop_type] = details
   end
   return details
end
]]

function AceFarmingService.rate_field_for_fertilize(field_layer, entity)
   local field = field_layer:get_component('stonehearth:farmer_field_layer'):get_farmer_field()
   local fertilizer_preference = field:get_fertilizer_preference()
   
   -- we only care about fields that are limited by fertilizer uri
   -- if it's available, prioritize that field first (1)
   -- if it's not available, prioritize it last (0)
   if fertilizer_preference.uri then
      local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(field_layer))
      local tracking_data = inventory:get_items_of_type(fertilizer_preference.uri)
      if tracking_data and tracking_data.items then
         for id, item in pairs(tracking_data.items) do
            if radiant.entities.can_acquire_lease(item, 'stonehearth_ace:fertilize', entity) then
               return 1
            end
         end
      end

      return 0
   else
      return self.rate_field(field_layer, entity)
   end
end

return AceFarmingService
