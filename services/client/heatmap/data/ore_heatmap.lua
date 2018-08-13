-- you must register a valid Lua 'class' file with the service to use for a heatmap; it must have the following properties: (* is always required, + is sometimes required)
-- *  name:                a string key used to identify/distinguish this heatmap from others
-- *  valuation_mode:      a string key used to identify how valuations are made: accepted values are 'entity' or 'location'
-- *  fn_get_heat_value:   a function that returns a heat 'value' when passed an entity or location point
--    default_heat_value:  optional; the default heat value for 'invalid' entities/locations
-- *  fn_heat_value_to_color: a function that returns a color when passed a heat value and the min and max recorded heat values
-- +  fn_heat_value_to_hilight:  a function that returns a highlight color (Point3) when passed a heat value and the min and max recorded heat values for 'entity' valuation_mode
--    default_color:       optional; the default color when a call to fn_heat_value_to_color returns nil
--    fn_compare_heat_values: optional; a function that returns a comparison value (-1, 0, or 1) when passed two heat values; if not specified, standard operators are used
--    fn_combine_heat_values: optional; a function that returns a combination of two heat values passed to it; if not specified, + is used
-- +  fn_is_entity_relevant:  a function that returns whether surrounding entities are important for heat value calculation in 'entity' valuation_mode
--    radius:              an integer that specifies how far from the central location to draw the heatmap; squared is the further distance for entity calculation
-- *  fn_filter_query_scene:  determine the best moused-over entity to use as the heatmap origin location; passed the current best location and one entity/location at a time
--    sample_denominator:  optional; a divisor by which an aggregate sum is divided when using 'entity' valuation_mode
--    raycast_origin:      optional; only for 'entity' valuation_mode
--    initialize:          optional; a function run when a heatmap is shown, with a callback function parameter

local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('ore_heatmap')
local get_block_kind_at = radiant.terrain.get_block_kind_at
local to_color4 = radiant.util.to_color4

local OreHeatmap = class()

OreHeatmap.name = 'ore_heatmap'
OreHeatmap.valuation_mode = 'location'
OreHeatmap.radius = 12
OreHeatmap._base_depth = 10
OreHeatmap._max_heat_value = 3
OreHeatmap._base_color = Point3(255, 128, 0) -- this gets combined with an alpha value based on the heat value

function OreHeatmap:initialize(fn_callback)
   if self:_check_initialized_done(fn_callback) then
      return
   elseif self._initializing then
      return
   end
   
   self._initializing = true

   -- stolen from stonehearth.services.client.terrain_highlight_service
   self._kind_to_entity_map = {}
   local config = radiant.terrain.get_config()
   for kind, entity_name in pairs(config.selectable_kinds) do
      self._kind_to_entity_map[kind] = radiant.entities.create_entity(entity_name)
   end

   -- Get the town entity so we can see whether we have bonuses that modify ore detection
   self._town = nil
   self._catalog_data = nil
   local player_id = _radiant.client.get_player_id()
   if not player_id then
      radiant.events.listen(radiant, 'radiant:client:server_ready', function()  -- Client doesn't know its player ID before then
         self:_do_initialization(_radiant.client.get_player_id(), fn_callback)
      end)
   else
      self:_do_initialization(player_id, fn_callback)
   end
end

function OreHeatmap:_do_initialization(player_id, fn_callback)
   _radiant.call_obj('stonehearth.town', 'get_town_entity_command', player_id)
      :done(function(response)
         self._town = response.town
         self:_check_initialized_done(fn_callback)
      end)
   -- Fetch the catalog so we can check whether something is a plant to apply town bonuses.
   _radiant.call('stonehearth:get_all_catalog_data')
      :done(function(response)
         self._catalog_data = response
         self:_check_initialized_done(fn_callback)
      end)
end

function OreHeatmap:_check_initialized_done(fn_callback)
   if self._town and self._catalog_data then
      self._initializing = nil
      if fn_callback then
         fn_callback()
      end
      
      return true
   end
   
   return false
end

function OreHeatmap:fn_get_heat_value(location)
   local depth = self._base_depth
   if self._town and self._town:get_data().town_bonuses['stonehearth:town_bonus:ore_detection'] then
      depth = depth * 2
   end

   -- we're using a subset of the harmonic series to represent ore at each depth n
   -- at reasonable depths (up to 50+) this shouldn't be maxing out (to 3) unless there's a ton of ore right at the surface
   local ore_count = 0
   for i = 0, -depth, -1 do
      local brick = location + Point3(0, i, 0)
      local kind = get_block_kind_at(brick)
      local ore_entity = self._kind_to_entity_map[kind]

      if ore_entity then
         ore_count = ore_count + 1 / math.max(0.1, location.y - brick.y)
         if ore_count >= self._max_heat_value then
            break
         end
      end
   end

   return math.min(ore_count, self._max_heat_value)
end

function OreHeatmap:fn_heat_value_to_color(heat_value)
   -- scale our color by scaling the transparency value (hopefully this works!) with _max_heat_value => 255
   return to_color4(self._base_color, heat_value * 255 / self._max_heat_value)
end

-- return values are [this rank, max rank value]: if you just want to say use this location, return 1, 1
function OreHeatmap:fn_filter_query_scene(best_location, query_result)
   local is_building = (query_result.entity:get_component('stonehearth:construction_data') or
                        query_result.entity:get_component('stonehearth:build2:structure') or
                        query_result.entity:get_component('stonehearth:floor'))
   if is_building and query_result.normal.y > 0.5 then  -- floor
      return 1, 1
   elseif query_result.entity:get_id() == radiant._root_entity_id then  -- terrain
      return 1, 1
   end
   
   return 0, 1
end

return OreHeatmap
