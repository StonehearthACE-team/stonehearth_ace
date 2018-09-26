-- you must register a valid Lua 'class' file with the service to use for a heatmap; it must have the following properties: (* is always required, + is sometimes required)
-- *  name:                a string key used to identify/distinguish this heatmap from others
-- *  valuation_mode:      a string key used to identify how valuations are made: accepted values are 'entity' or 'location'
-- +  fn_get_entity_heat_value:      a function that returns a heat 'value' when passed an entity
-- +  fn_get_location_heat_value:    a function that returns a heat 'value' when passed a location point
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
--    shape:               optional; defaults to 'square', only other supported option is 'circle'

local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('wilderness_heatmap')
local wilderness_util = require 'lib.wilderness.wilderness_util'

local WildernessHeatmap = class()

WildernessHeatmap.name = 'wilderness_heatmap'
WildernessHeatmap.valuation_mode = 'entity'
WildernessHeatmap.radius = stonehearth.constants.wilderness.SAMPLE_RADIUS
WildernessHeatmap.sample_denominator = stonehearth.constants.wilderness.SAMPLE_DENOMINATOR

function WildernessHeatmap:initialize(fn_callback)
   if self:_check_initialized_done(fn_callback) then
      return
   elseif self._initializing then
      return
   end
   
   self._initializing = true
   self._catalog_data = nil
   self._catalog_fn = function(uri)
      return self._catalog_data[uri]
   end
   self:_do_initialization(fn_callback)
end

function WildernessHeatmap:_do_initialization(fn_callback)
   -- Fetch the catalog so we can properly use the wilderness_util from the client
   _radiant.call('stonehearth:get_all_catalog_data')
      :done(function(response)
         self._catalog_data = response
         self:_check_initialized_done(fn_callback)
      end)
end

function WildernessHeatmap:_check_initialized_done(fn_callback)
   if self._catalog_data then
      self._initializing = nil
      if fn_callback then
         fn_callback()
      end
      
      return true
   end
   
   return false
end

function WildernessHeatmap:fn_get_entity_heat_value(entity, sampling_region)
   return wilderness_util.get_value_from_entity(entity, self._catalog_fn, sampling_region)
end

function WildernessHeatmap:fn_get_location_heat_value(location)
   return wilderness_util.get_value_from_terrain(location)
end

function WildernessHeatmap:fn_heat_value_to_color(value)
   for _, level in ipairs(stonehearth.constants.wilderness.LEVELS) do
      if value < level.max then
         return Color4(unpack(level.heatmap_color))
      end
   end
end

function WildernessHeatmap:fn_heat_value_to_hilight(value)
   value = value / self.sample_denominator
   for _, level in ipairs(stonehearth.constants.wilderness.LEVELS) do
      if value < level.max then
         local color = Point3(unpack(level.heatmap_hilight))
         return color
      end
   end
end

function WildernessHeatmap:fn_is_entity_relevant(entity)
   return wilderness_util.has_wilderness_value(entity, self._catalog_fn)
end

return WildernessHeatmap
