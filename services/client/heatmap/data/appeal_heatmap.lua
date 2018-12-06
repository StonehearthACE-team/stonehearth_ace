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
local log = radiant.log.create_logger('appeal_heatmap')
local get_entity_data = radiant.entities.get_entity_data

local AppealHeatmap = class()

AppealHeatmap.name = 'appeal_heatmap'
AppealHeatmap.valuation_mode = 'entity'
AppealHeatmap.shape = 'circle'
AppealHeatmap.radius = stonehearth.constants.appeal.APPEAL_SAMPLE_RADIUS
AppealHeatmap.sample_denominator = stonehearth.constants.appeal.APPEAL_SAMPLE_DENOMINATOR
AppealHeatmap._vitality_multiplier = stonehearth.constants.town_progression.bonuses.VITALITY_PLANT_APPEAL_MULTIPLIER

function AppealHeatmap:initialize(fn_callback)
   if self:_check_initialized_done(fn_callback) then
      return
   elseif self._initializing then
      return
   end
   
   -- Get the town entity so we can see whether we have the "vitality" town bonus which affects the appeal of plants.
   -- If we ever have more town bonuses that affect appeal, we'll need a generic hook, but for now, let's keep it light.
   self._initializing = true
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

function AppealHeatmap:_do_initialization(player_id, fn_callback)
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

function AppealHeatmap:_check_initialized_done(fn_callback)
   if self._town and self._catalog_data then
      self._initializing = nil
      if fn_callback then
         fn_callback()
      end
      
      return true
   end
   
   return false
end

function AppealHeatmap:fn_get_entity_heat_value(entity)
   local appeal_data = radiant.entities.get_entity_data(entity, 'stonehearth:appeal')
   local appeal = appeal_data and appeal_data.appeal

   if not appeal then
      return nil
   end

   local item_quality = radiant.entities.get_item_quality(entity)
   appeal = radiant.entities.apply_item_quality_bonus('appeal', appeal, item_quality)

   -- Apply the "vitality" town bonus if it's applicable. If we ever have more of these,
   -- we'll need a generic hook, but for now, let's keep it light.
   if self._town and self._town:get_data().town_bonuses['stonehearth:town_bonus:vitality'] then
      local uri = type(entity) == 'string' and entity or entity:get_uri()
      local catalog_data = self._catalog_data[uri]
      if catalog_data and catalog_data.category == 'plants' then
         appeal = radiant.math.round(appeal * self._vitality_multiplier)
      end
   end

   return appeal
end

function AppealHeatmap:fn_heat_value_to_color(appeal)
   for _, level in ipairs(stonehearth.constants.appeal.LEVELS) do
      if appeal < level.max then
         return Color4(unpack(level.heatmap_color))
      end
   end
end

function AppealHeatmap:fn_heat_value_to_hilight(appeal)
   local color
   if appeal > 60 then
      color = Point3(0.90, 0.65, 0.20)
   elseif appeal > 0 then
      color = Point3(1.00, 0.55, 0.00)
   elseif appeal > -10 then
      color = Point3(0.46, 0.49, 1.00)
   else
      color = Point3(0.20, 0.20, 0.60)
   end
   return color
end

function AppealHeatmap:fn_is_entity_relevant(item)
   local appeal_data = get_entity_data(item, 'stonehearth:appeal')
   return appeal_data and rawget(appeal_data, 'appeal') and rawget(appeal_data, 'appeal') ~= 0
end

return AppealHeatmap
