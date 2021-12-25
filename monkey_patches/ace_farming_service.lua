local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local FarmingService = require 'stonehearth.services.server.farming.farming_service'
AceFarmingService = class()

local log = radiant.log.create_logger('farming_service')

function AceFarmingService:_load_field_types()
   local data = radiant.resources.load_json('stonehearth:farmer:all_crops')
   self._field_types = data.field_types
end

function AceFarmingService:get_field_types()
   return self._field_types
end

function AceFarmingService:get_field_type(field_type)
   return self._field_types[field_type]
end

function AceFarmingService:create_new_field(session, location, size, field_type, rotation)
   -- A little sanitization: what we get from the client isn't exactly a Point3
   location = Point3(location.x, location.y, location.z)
   local entity = radiant.entities.create_entity('stonehearth:farmer:field', { owner = session.player_id })
   radiant.terrain.place_entity(entity, location)

   self:_add_region_components(entity, size)

   local town = stonehearth.town:get_town(session.player_id)

   local farmer_field = entity:get_component('stonehearth:farmer_field')
   farmer_field:on_field_created(town, size, field_type, rotation)

   return entity
end

function AceFarmingService:_ensure_herbalist_crops_loaded()
   if not self._herbalist_crops then
      local herbalist_crops_data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter:crops')
      self._herbalist_crops = herbalist_crops_data.crops
   end

   return self._herbalist_crops
end

function AceFarmingService:_get_crop_list(session)
   local player_id = session.player_id
   local crop_list = self._data.player_crops[player_id]
   if not crop_list then
      -- xxx: look this up from the player info when that is avaiable
      local kingdom = stonehearth.population:get_population(player_id)
                                                :get_kingdom()

      -- start out with the default crops for this player's kingdom.
      crop_list = {}
      local all_crops = self._all_crops
      local kingdom_crops = self._initial_crops[kingdom]
      if kingdom_crops and all_crops then
         for key, crop in pairs(all_crops) do
            crop_list[key] = {
               crop_key = key,
               crop_type = crop.crop_type,
               crop_info = self:get_crop_details(crop.crop_type),
               crop_level_requirement = crop.level_requirement,
               ordinal = crop.ordinal,
               initial_crop = kingdom_crops[key],
               field_types = crop.field_types or {farm = true}
            }
         end

         -- then also add any herbalist crops
         local herbalist_crops = self:_ensure_herbalist_crops_loaded()
         if herbalist_crops then
            for key, crop in pairs(herbalist_crops) do
               log:debug('adding herbalist crop %s to crop list...', key)
               if not crop_list[key] then
                  crop_list[key] = {}
               end
               crop_list[key].herbalist_crop_info = {
                  crop_key = key,
                  crop_type = crop.product_uri,
                  crop_info = self:get_herbalist_crop_details(crop),
                  crop_level_requirement = crop.level,
                  ordinal = crop.ordinal,
                  initial_crop = kingdom_crops[key],
                  hidden = crop.hidden,
                  --planter_types = {}   -- do we want/need to include this here?
               }
            end
         end
      end
      self._data.player_crops[player_id] = crop_list
   end
   return crop_list
end

function AceFarmingService:get_herbalist_crop_details(crop_data)
   local uri = crop_data.product_uri
   local details = self._crop_details[uri]
   if not details then
      details = {}
      details.uri = uri
      details.name = crop_data.display_name
      details.description = crop_data.description
      details.icon = crop_data.icon
      self._crop_details[uri] = details
   end
   return details
end

--- Given a new crop type, record some important things about it
function AceFarmingService:get_crop_details(crop_type)
   local details = self._crop_details[crop_type]
   if not details then
      local catalog_data = stonehearth.catalog:get_catalog_data(crop_type)
      details = {}
      details.uri = crop_type
      details.name = catalog_data.display_name
      details.description = catalog_data.description
      details.icon = catalog_data.icon
      local json = radiant.resources.load_json(crop_type)
      if json and json.components then
         local growing_data = json.components['stonehearth:growing']
         local crop_data = json.components['stonehearth:crop']
         if growing_data then
            if growing_data.preferred_seasons then
               local biome_uri = stonehearth.world_generation:get_biome_alias()
               local seasons = stonehearth.seasons:get_seasons()
               if biome_uri and seasons then  -- Hacky protection against races; should never happen in theory.
                  local preferred_seasons = growing_data.preferred_seasons[biome_uri]
                  details.preferred_seasons = {}
                  if preferred_seasons then
                     for _, season_id in ipairs(preferred_seasons) do
                        if seasons[season_id] then
                           details.preferred_seasons[season_id] = seasons[season_id].display_name
                        end
                     end
                  end
               end
            end

            details.preferred_climate = growing_data.preferred_climate
            details.flood_period_multiplier = growing_data.flood_period_multiplier or stonehearth.constants.farming.DEFAULT_FLOODED_GROWTH_TIME_MULTIPLIER
            details.frozen_period_multiplier = growing_data.frozen_period_multiplier or stonehearth.constants.farming.DEFAULT_FROZEN_GROWTH_TIME_MULTIPLIER
            details.require_flooding_to_grow = growing_data.require_flooding

            if crop_data then
               local harvest_stage = 1
               for index, stage in ipairs(growing_data.growth_stages) do
                  if stage.model_name == crop_data.harvest_threshhold then
                     harvest_stage = index
                     break
                  end
               end
               local total_time = (harvest_stage - 1) * stonehearth.calendar:parse_duration(growing_data.growth_period)
               local total_growth_time = stonehearth.calendar:convert_to_date(total_time)
               
               -- we only want to express the time in terms of days and hours; round up anything below that
               local _time_durations = stonehearth.calendar:get_time_durations()
               if total_growth_time.minute > 0 or total_growth_time.second > 0 then
                  total_growth_time.hour = total_growth_time.hour + 1
                  total_growth_time = stonehearth.calendar:convert_to_date(total_growth_time.day * _time_durations.day + total_growth_time.hour * _time_durations.hour)
               end
               details.total_growth_time = total_growth_time

               if total_time <= stonehearth.calendar:parse_duration(stonehearth.constants.farming.crop_growth_times.SHORT) then
                  details.growth_time = 'short'
               elseif total_time <= stonehearth.calendar:parse_duration(stonehearth.constants.farming.crop_growth_times.FAIR) then
                  details.growth_time = 'fair'
               else
                  details.growth_time = 'long'
               end
            end
         end
      end
      self._crop_details[crop_type] = details
   end
   return details
end

-- changed the way this works to be similar to other tasks being generated instead of a constant searching for fertilizable fields
-- function AceFarmingService.rate_field_for_fertilize(field_layer, entity)
--    local field = field_layer:get_component('stonehearth:farmer_field_layer'):get_farmer_field()
--    local fertilizer_preference = field:get_fertilizer_preference()
   
--    -- we only care about fields that are limited by fertilizer uri
--    -- if it's available, prioritize that field first (1)
--    -- if it's not available, prioritize it last (0)
--    if fertilizer_preference.uri then
--       local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(field_layer))
--       local tracking_data = inventory:get_items_of_type(fertilizer_preference.uri)
--       if tracking_data and tracking_data.items then
--          for id, item in pairs(tracking_data.items) do
--             if radiant.entities.can_acquire_lease(item, 'stonehearth_ace:fertilize', entity) then
--                return 1
--             end
--          end
--       end

--       return 0
--    else
--       return self.rate_field(field_layer, entity)
--    end
-- end

function AceFarmingService:get_fertilizer_quality_range()
   local fertilizer_quality_range = self._fertilizer_quality_range
   if not fertilizer_quality_range then
      -- get the min and max ilevels of fertilizers in the game and use that to bound the rating function
      local fertilizer = stonehearth.catalog:get_material_object('fertilizer')
      if fertilizer then
         local fertilizers = stonehearth.catalog:get_materials_to_matching_uris()[fertilizer:get_id()]
         local min, max
         for uri, _ in pairs(fertilizers) do
            local data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:fertilizer')
            local ilevel = data and data.ilevel
            if ilevel then
               min = math.min(min or ilevel, ilevel)
               max = math.max(max or ilevel, ilevel)
            end
         end

         if min and max then
            fertilizer_quality_range = {
               min = min,
               max = max
            }
         end
      end

      if not fertilizer_quality_range then
         fertilizer_quality_range = {
            min = 0,
            max = 1
         }
      end
   
      fertilizer_quality_range.range = math.max(1, fertilizer_quality_range.max - fertilizer_quality_range.min)
      self._fertilizer_quality_range = fertilizer_quality_range
   end

   return fertilizer_quality_range
end

return AceFarmingService
