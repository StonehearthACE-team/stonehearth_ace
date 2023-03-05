local RaycastLib = require 'ai.lib.raycast_lib'
local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Point2 = _radiant.csg.Point2
local log = radiant.log.create_logger('heatmap')
local is_temporary_entity = radiant.entities.is_temporary_entity

local HeatmapService = class()

function HeatmapService:initialize()
   self._sv.current_probe_value = nil  -- Tells the browser about the last value.
   
   -- heatmaps need to be registered with the service to be used
   self._heatmap_keys = radiant.resources.load_json('stonehearth_ace:heatmap:keys').heatmaps or {}
   self._heatmaps = {}
   for key, heatmap in pairs(self._heatmap_keys) do
      self:_import_settings(key, heatmap)
   end
   
   -- Set when the heatmap is shown or hidden.
   self._settings = nil	-- A table containing specifications for the heatmap's valuation and appearance
   self._heatmap_node = nil  -- The Debug Shapes render node to which tiles are attached.
   self._mouse_trace = nil  -- A trace on mouse movement to find where to probe.

   -- State that updates as the cursor moves.
   self._current_probe_coordinates = nil  -- The coordinate of the pending probe.
   self._last_probe_coordinates = nil  -- The coordinate of the last probe, to avoid re-probing if it hasn't changed.
   self._hilighted_item_ids = {}  -- A list of IDs of the entities currently highlighted.
   self._saved_tiles = {}  -- A map from stringified tile coordinate to heat value for tiles we already examined;
                           -- a performance cache that is only invalidated when the heatmap is hidden.

   self:hide_heatmap_command()  -- Make sure it's off by default.
end

function HeatmapService:_import_settings(key, settings_key)
   -- if we already have this heatmap loaded up, return the settings for it
   -- otherwise, check the heatmap key data and load the settings file
   local settings = self._heatmaps[key]
   
   if not settings then
      settings_key = settings_key or self._heatmap_keys[key]
      if settings_key and settings_key.settings_file then
         settings = radiant.mods.load_script(settings_key.settings_file)
         self._heatmaps[key] = settings
         
         -- if this heatmap has other things it needs to set up, let it do that now, but no callback because we don't care now
         if settings.initialize then
            settings:initialize()
         end
      end
   end
   
   if not (settings and settings.name) then
      return nil
   end
   
   return settings
end

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
--    fn_filter_query_scene:  optional; determine the best moused-over entity to use as the heatmap origin location; passed the current best location and one entity/location at a time
--    sample_denominator:  optional; a divisor by which an aggregate sum is divided when using 'entity' valuation_mode
--    raycast_origin:      optional; only for 'entity' valuation_mode
--    initialize:          optional; a function run when a heatmap is shown, with a callback function parameter
--    shape:               optional; defaults to 'square', only other supported option is 'circle'
--    checkerboard:        optional; whether only alternating grid coords should be calculated and the rest smoothed; defaults to false
function HeatmapService:show_heatmap_command(session, response, settings_key)
   self._settings = self:_import_settings(settings_key)
   -- if we fail to import the settings, abort
   if not self._settings and self._settings.name then
      return
   end
   
   self._settings.fn_get_entity_heat_value = self._settings.fn_get_entity_heat_value or function() end
   self._settings.fn_get_location_heat_value = self._settings.fn_get_location_heat_value or function() end
   self._settings.default_heat_value = self._settings.default_heat_value or 0
   self._settings.default_color = self._settings.default_color or Color4(255, 0, 255, 255) -- bright magenta should clue you in that there's a problem, because who would use that color normally?
   self._settings.radius = self._settings.radius or 0
   self._settings.MAX_SQUARED_RADIUS = self._settings.radius * self._settings.radius
   self._settings.sample_denominator = (self._settings.sample_denominator ~= 0 and self._settings.sample_denominator) or 1
   self._settings.raycast_origin = self._settings.raycast_origin or Point3(0, stonehearth.constants.raycast.STANDING_RAYCAST_HEIGHT, 0)
   self._settings.shape = self._settings.shape or 'square'
   self._settings.checkerboard = self._settings.checkerboard or false

   self._heatmap_node = RenderRootNode:add_debug_shapes_node(self._settings.name .. ' heatmap for ' .. tostring(self._entity))
   self._heatmap_node:set_use_custom_alpha(true)
   self._saved_tiles = {}
   self._saved_checkerboard = {}
   
   -- if this heatmap has other things it needs to set up, let it do that now, with a callback in case they need to do deferred calls
   if self._settings.initialize then
      self._settings:initialize(function() self:_on_initialized() end)
   end

   self._deferred = response
end

function HeatmapService:_on_initialized()
   self._mouse_trace = stonehearth.input:capture_input('HeatmapService')
                              :on_mouse_event(function(e)
                                    return self:_on_mouse_event(e)
                                 end)
                              :on_keyboard_event(function(e)
                                    return self:_on_keyboard_event(e)
                                 end)
   _radiant.renderer.set_global_uniform('global_desaturate_multiplier', 1.0)
   _radiant.renderer.set_pipeline_stage_enabled('FillBasedSelection', true)
end

function HeatmapService:hide_heatmap_command(session, response)
   if self._mouse_trace then
      self._mouse_trace:destroy()
      self._mouse_trace = nil
   end
   if self._heatmap_node then
      self._heatmap_node:destroy()
      self._heatmap_node = nil
   end
   if self._deferred then
      self._deferred:resolve({hidden = true})
      self._deferred = nil
   end
   self._last_probe_coordinates = nil
   for _, item_id in ipairs(self._hilighted_item_ids) do
      _radiant.client.unhilight_entity(item_id)
   end
   _radiant.renderer.set_global_uniform('global_desaturate_multiplier', 0.0)
   _radiant.renderer.set_pipeline_stage_enabled('FillBasedSelection', false)
end

function HeatmapService:is_heatmap_active_command(session, response, map_type)
   return { is_active = (self._heatmap_node ~= nil or self.map_type ~= map_type) }
end

function HeatmapService:destroy()
   self:hide_heatmap_command()
end

-- TODO: change this to be a datastore like the clock object so heatmaps can be added/removed dynamically?
function HeatmapService:get_heatmaps_command(session, response)
   local heatmaps = {}
   for key, _ in pairs(self._heatmaps) do
      heatmaps[key] = self._heatmap_keys[key]
   end

   return { heatmaps = heatmaps }
end

function HeatmapService:_heat_value_to_color(value, min_value, max_value)
   return self._settings:fn_heat_value_to_color(value, min_value, max_value) or self._settings.default_color
end

function HeatmapService:_heat_value_to_hilight(value, min_value, max_value)
   local color
   if self._settings.fn_heat_value_to_hilight then
      color = self._settings:fn_heat_value_to_hilight(value, min_value, max_value)
   end
   return color or self._settings.default_color
end

function HeatmapService:_compare_heat_values(val_a, val_b)
   if self._settings.fn_compare_heat_values then
      return self._settings:fn_compare_heat_values(val_a, val_b)
   else
      return (val_a < val_b and -1) or (val_a > val_b and 1) or 0
   end
end

function HeatmapService:_combine_heat_values(val_a, val_b)
   if val_a == nil then
      val_a = self._settings.default_heat_value
   end
   if val_b == nil then
      val_b = self._settings.default_heat_value
   end
   if self._settings.fn_combine_heat_values then
      return self._settings:fn_combine_heat_values(val_a, val_b)
   else
      return val_a + val_b
   end
end

function HeatmapService:_on_mouse_event(e)
   if not self._heatmap_node then
      return
   end

   -- if the user right-clicked or pressed escape, cancel out of the heatmap mode
   if e:down(2) then
      self:hide_heatmap_command()
      return
   end

   local best_brick = nil
   local cur_rank, new_rank, max_rank
   for result in _radiant.client.query_scene(e.x, e.y):each_result() do
      if radiant.entities.exists(result.entity) then
         new_rank, max_rank = self:fn_filter_query_scene(best_brick, result)
         if new_rank >= max_rank then
            best_brick = result.brick
            break
         elseif not best_brick or new_rank > cur_rank then
            best_brick = result.brick
            cur_rank = new_rank
         end
      end
   end
   if best_brick then
      local current_coordinates = Point3(best_brick.x, best_brick.y, best_brick.z)
      if current_coordinates ~= self._last_probe_coordinates then
         self:_update_tiles(current_coordinates)
         if self._settings.valuation_mode == 'entity' then
            self:_update_item_highlights(current_coordinates)
         end
         self._last_probe_coordinates = current_coordinates
      end
   end
end

function HeatmapService:_on_keyboard_event(e)
   -- if the user right-clicked or pressed escape, cancel out of the heatmap mode
   -- how to detect escape press? do we have to set up a hotkey? or it could be implemented in js
end

-- return values are [this rank, max rank value]: if you just want to say use this location, return 1, 1
function HeatmapService:fn_filter_query_scene(best_location, query_result)
   if self._settings.fn_filter_query_scene then
      self._settings:fn_filter_query_scene(best_location, query_result)
   else
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
end

function HeatmapService:_update_tiles(origin)
   self._heatmap_node:clear()
   
   local min_val, max_val = self:_get_min_max_heat_values()

   local radius = self._settings.radius
   for dx = -radius, radius do
      for dz = -radius, radius do
         local x = origin.x + dx
         local y = origin.y
         local z = origin.z + dz
         local point = Point3(x, y, z)
         if not self._settings.checkerboard or (x + z) % 2 == 0 then
            if self._settings.shape ~= 'circle' or point:distance_to(origin) <= radius then
               local key = self:_get_location_key(x, y, z)
               local heat_value
               if self._saved_tiles[key] then   -- if we already have a value for this space, no need to calculate a new one
                  heat_value = self._saved_tiles[key]
               elseif self._settings.valuation_mode == 'entity' then -- if we're evaluating entities, use an aggregate of the entities in the surrounding area
                  local items = self:_get_surrounding_items(point)
                  heat_value = self:_get_location_heat_value(point) + self:_get_aggregate_heat_value_of_items(items)
                  self._saved_tiles[key] = heat_value
               elseif self._settings.valuation_mode == 'location' then  -- if we're evaluating a location, just pass the location to the evaluator function
                  heat_value = self:_get_location_heat_value(point)
                  self._saved_tiles[key] = heat_value
               end
               
               if point == origin then
                  self._sv.current_probe_value = heat_value
                  self.__saved_variables:mark_changed()
               end
               
               local color = self:_heat_value_to_color(heat_value, min_val, max_val)
               -- this used to be "x - 0.5" but it looked incorrectly offset
               self._heatmap_node:add_filled_xz_quad(Point3(x, y + 1.5, z - 0.5), Point2(1, 1), color)
            end
         end
      end
   end

   if self._settings.checkerboard then
      for dx = -radius, radius do
         for dz = -radius, radius do
            local x = origin.x + dx
            local y = origin.y
            local z = origin.z + dz
            local point = Point3(x, y, z)
            if (x + z) % 2 == 1 then
               if self._settings.shape ~= 'circle' or point:distance_to(origin) <= radius then
                  local key = self:_get_location_key(x, y, z)
                  local heat_value
                  if not self._saved_checkerboard[key] or not self._saved_checkerboard[key].mode then
                     -- if we don't have a saved value, combine all the neighboring saved tile values into a sequence to find the mode
                     local neighbor_values = {}
                     self._saved_checkerboard[key] = neighbor_values
                     table.insert(neighbor_values, self._saved_tiles[self:_get_location_key(x - 1, y, z)])
                     table.insert(neighbor_values, self._saved_tiles[self:_get_location_key(x + 1, y, z)])
                     table.insert(neighbor_values, self._saved_tiles[self:_get_location_key(x, y, z - 1)])
                     table.insert(neighbor_values, self._saved_tiles[self:_get_location_key(x, y, z + 1)])
                  end
                  heat_value = self:_get_mode_heat_value(self._saved_checkerboard[key])
                  
                  if point == origin then
                     self._sv.current_probe_value = heat_value
                     self.__saved_variables:mark_changed()
                  end
                  
                  local color = self:_heat_value_to_color(heat_value, min_val, max_val)
                  -- this used to be "x - 0.5" but it looked incorrectly offset
                  self._heatmap_node:add_filled_xz_quad(Point3(x, y + 1.5, z - 0.5), Point2(1, 1), color)
               end
            end
         end
      end
   end

   self._heatmap_node:create_buffers()
end

function HeatmapService:_get_location_key(x, y, z)
   return string.format('%f,%f,%f', x, y, z)
end

function HeatmapService:_get_mode_heat_value(values)
   -- this is used for checkerboard mode, where alternating coords' values are determined by their four cardinal neighboring coords
   if not values or not next(values) then
      return self._settings.default_heat_value
   end

   if values.mode then
      return values.mode
   end
   
   local max = 1
   local freq = {[1] = 1}
   for i = 2, #values do
      local matched = false
      for id, _ in pairs(freq) do
         if self:_compare_heat_values(values[i], values[id]) == 0 then
            freq[id] = freq[id] + 1
            max = math.max(max, freq[id])
            matched = true
            break
         end
      end
      if not matched then
         freq[i] = 1
      end
   end

   local best_value
   for id, value in ipairs(values) do
      if freq[id] and freq[id] >= max and (not best_value or self:_compare_heat_values(value, best_value) > 0) then
         best_value = value
      end
   end
   if #values >= 4 then -- this value could perhaps be variable if we want to "generify" this function
      -- if we have all our neighboring values, go ahead and set the mode here so we don't have to recalculate it
      values.mode = best_value
   end

   return best_value
end

function HeatmapService:_get_min_max_heat_values()
   local min_val, max_val
   for _, val in pairs(self._saved_tiles) do
      if not min_val or self:_compare_heat_values(val, min_val) < 0 then
         min_val = val
      end
      if not max_val or self:_compare_heat_values(val, max_val) > 0 then
         max_val = val
      end
   end
   return min_val, max_val
end

function HeatmapService:_update_item_highlights(origin)
   for _, item_id in ipairs(self._hilighted_item_ids) do
      _radiant.client.unhilight_entity(item_id)
   end
   self._hilighted_item_ids = {}
   
   local min_val, max_val = self:_get_min_max_heat_values()
   for _, sampled_item in ipairs(self:_get_surrounding_items(Point3(origin.x, origin.y, origin.z), 1)) do
      local item = sampled_item.item
      local heat_value = self:_get_entity_heat_value(item, sampled_item.sampling_region)
      local color = self:_heat_value_to_hilight(heat_value)
      --log:error('hilighting %s color %s', item:get_uri(), tostring(color))
      _radiant.client.hilight_entity(item, color)
      table.insert(self._hilighted_item_ids, item:get_id())
   end
end

function HeatmapService:_get_surrounding_items(origin, extra_radius)
   local r = self._settings.radius + (extra_radius or 0)
   local raycast_origin = origin + self._settings.raycast_origin
   local sampling_cube = Cube3(Point3.zero):inflated(Point3(r, r, r)):translated(raycast_origin)
   local result = {}
   local get_entity_data = radiant.entities.get_entity_data
   local table_insert = table.insert
   for _, item in pairs(radiant.terrain.get_entities_in_cube(sampling_cube)) do
      if not is_temporary_entity(item) and self:_is_entity_relevant(item, raycast_origin) then
         table_insert(result, {item = item, sampling_region = Region3(sampling_cube)})
      end
   end
   return result
end

function HeatmapService:_is_entity_relevant(item, raycast_origin)
   if self._settings:fn_is_entity_relevant(item) then
      if self._settings.shape ~= 'circle' then
         return true
      else
         local target_point = item:get_component('mob'):get_world_location()
         if target_point then
            if raycast_origin:distance_to_squared(target_point) <= self._settings.MAX_SQUARED_RADIUS then
               return true
            end
         end
      end
   end
   
   return false
end

function HeatmapService:_get_aggregate_heat_value_of_items(items)
   local total_heat_value = 0
   for _, sampled_item in ipairs(items) do
      total_heat_value = self:_combine_heat_values(total_heat_value, self:_get_entity_heat_value(sampled_item.item, sampled_item.sampling_region))
   end
   return total_heat_value / self._settings.sample_denominator
end

function HeatmapService:_get_entity_heat_value(item, sampling_region)
   return self._settings:fn_get_entity_heat_value(item, sampling_region) or self._settings.default_heat_value
end

function HeatmapService:_get_location_heat_value(item)
   return self._settings:fn_get_location_heat_value(item) or self._settings.default_heat_value
end

return HeatmapService
