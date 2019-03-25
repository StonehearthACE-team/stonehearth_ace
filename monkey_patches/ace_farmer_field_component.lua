local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('farmer_field')
local FarmerFieldComponent = require 'stonehearth.components.farmer_field.farmer_field_component'

local AceFarmerFieldComponent = class()

local RECALCULATE_THRESHOLD = 0.04
local SUNLIGHT_CHECK_TIME = '4h'

AceFarmerFieldComponent._ace_old_restore = FarmerFieldComponent.restore
function AceFarmerFieldComponent:restore()
   self._is_restore = true
   self._sv.water_level = nil
   self._sv.last_set_water_level = nil
   
   self:_ace_old_restore()

   -- if this is an old farm that doesn't have full details, reload the details
   if self._sv.current_crop_details and not self._sv.current_crop_details.flood_period_multiplier then
      self._sv.current_crop_details = stonehearth.farming:get_crop_details(self._sv.current_crop_alias)
      self.__saved_variables:mark_changed()
   end

   self:_cache_best_levels()
end

function AceFarmerFieldComponent:post_activate()
   --self._flood_listeners = {}
   local biome = stonehearth.world_generation:get_biome()
   self._biome_sunlight = biome.sunlight or 1
   self._biome_humidity = biome.humidity or 0
   
   if not self._sv.sunlight_level then
      self._sv.sunlight_level = 1
   end
   if not self._sv.humidity_level then
      self._sv.humidity_level = 0
   end
   if not self._sv._water_level then
      self._sv._water_level = 0
   end
   if not self._sv.flooded then
      self._sv.flooded = false
   end

   if self._is_restore then
      self:_create_water_listener()
      --self:_create_flood_listeners()
      self:_create_climate_listeners()
   end

   self:_ensure_crop_counts()
   self:_ensure_fertilize_layer()
   self:_ensure_fertilizer_preference()
end

function AceFarmerFieldComponent:_ensure_crop_counts()
   -- make sure we're properly tracking fertilized counts and flooded counts
   local size = self._sv.size
   local contents = self._sv.contents
   
   if not self._sv.num_fertilized then
      local num_fertilized = 0
      for x=1, size.x do
         for y=1, size.y do
            local dirt_plot = contents[x][y]
            if dirt_plot and dirt_plot.is_fertilized then
               num_fertilized = num_fertilized + 1
            end
         end
      end

      self._sv.num_fertilized = num_fertilized
      self.__saved_variables:mark_changed()
   end

   -- if not self._sv.num_flooded then
   --    local num_flooded = 0
   --    for x=1, size.x do
   --       for y=1, size.y do
   --          local dirt_plot = contents[x][y]
   --          if dirt_plot and dirt_plot.contents then
   --             if dirt_plot.contents:add_component('stonehearth:growing'):is_flooded() then
   --                num_flooded = num_flooded + 1
   --             end
   --          end
   --       end
   --    end

   --    self._sv.num_flooded = num_flooded
   --    self.__saved_variables:mark_changed()
   -- end

   if not self._sv._queued_overwatered then
      self._sv._queued_overwatered = {}
   end
end

function AceFarmerFieldComponent:_ensure_fertilize_layer()
   if not self._sv._fertilizable_layer then
      self._sv._fertilizable_layer = self:_create_field_layer('stonehearth_ace:farmer:field_layer:fertilizable')
      if self._is_restore then
         self._sv._fertilizable_layer:get_component('destination')
                        :set_reserved(_radiant.sim.alloc_region3()) -- xxx: clear the existing one from cpp land!
                        :set_auto_update_adjacent(true)
      end
      table.insert(self._field_listeners, radiant.events.listen(self._sv._fertilizable_layer, 'radiant:entity:pre_destroy', self, self._on_field_layer_destroyed))
   end
end

function AceFarmerFieldComponent:_ensure_fertilizer_preference()
   if not self._sv.fertilizer_preference then
      self._sv.fertilizer_preference = self:_get_default_fertilizer_preference()
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_get_default_fertilizer_preference()
   local default = stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'default_fertilizer', '1')
   if tonumber(default) then
      return { quality = tonumber(default) }
   else
      return { uri = default }
   end
end

function AceFarmerFieldComponent:get_contents()
   return self._sv.contents
end

AceFarmerFieldComponent._ace_old_on_field_created = FarmerFieldComponent.on_field_created
function AceFarmerFieldComponent:on_field_created(town, size)
   self:_ace_old_on_field_created(town, size)
   radiant.terrain.place_entity(self._sv._fertilizable_layer, self._location)
   self._sv._queued_overwatered = {}

   self:_create_water_listener()
   self:_create_climate_listeners()
   self:_check_sky_visibility()
end

AceFarmerFieldComponent._ace_old_notify_till_location_finished = FarmerFieldComponent.notify_till_location_finished
function AceFarmerFieldComponent:notify_till_location_finished(location)
   self:_ace_old_notify_till_location_finished(location)
   
   local offset = location - radiant.entities.get_world_grid_location(self._entity)
   local x = offset.x + 1
   local y = offset.z + 1
   local key = x .. '|' .. y
   if self._sv._queued_overwatered[key] then
      self._sv.contents[x][y].overwatered_model = self:_get_overwatered_model()
      self._sv._queued_overwatered[key] = nil
   end
end

AceFarmerFieldComponent._ace_old_notify_plant_location_finished = FarmerFieldComponent.notify_plant_location_finished
function AceFarmerFieldComponent:notify_plant_location_finished(location)
   self:_ace_old_notify_plant_location_finished(location)

   local p = Point3(location.x - self._location.x, 0, location.z - self._location.z)
   local fertilizable_layer = self._sv._fertilizable_layer
   local fertilizable_layer_region = fertilizable_layer:get_component('destination'):get_region()

   fertilizable_layer_region:modify(function(cursor)
      cursor:add_point(p)
   end)
end

function AceFarmerFieldComponent:notify_crop_fertilized(location)
   local p = Point3(location.x - self._location.x, 0, location.z - self._location.z)
   local fertilizable_layer = self._sv._fertilizable_layer
   local fertilizable_layer_region = fertilizable_layer:get_component('destination'):get_region()
   fertilizable_layer_region:modify(function(cursor)
      cursor:subtract_point(p)
   end)

   self:_update_crop_fertilized(p.x + 1, p.z + 1, true)
end

function AceFarmerFieldComponent:notify_crop_harvested(location)
   self:_update_crop_fertilized(location.x - self._location.x + 1, location.z - self._location.z + 1, false)
end

AceFarmerFieldComponent._ace_old_plant_crop_at = FarmerFieldComponent.plant_crop_at
function AceFarmerFieldComponent:plant_crop_at(x_offset, z_offset)
   local crop = self:_ace_old_plant_crop_at(x_offset, z_offset)

   local growing_comp = crop and crop:add_component('stonehearth:growing')
	if growing_comp then
      growing_comp:set_growth_factors(self._sv.humidity_level, self._sv.sunlight_level)
      -- self:_create_flood_listener(crop)
      -- if growing_comp:is_flooded() then
      --    self._sv.num_flooded = self._sv.num_flooded + 1
      --    self.__saved_variables:mark_changed()
      -- end
	end
end

-- AceFarmerFieldComponent._ace_old_notify_crop_destroyed = FarmerFieldComponent.notify_crop_destroyed
-- function AceFarmerFieldComponent:notify_crop_destroyed(x, z)
--    local dirt_plot = self._sv.contents and self._sv.contents[x][z]
--    if dirt_plot and dirt_plot.contents then
--       self:_destroy_flood_listener(dirt_plot.contents:get_id())
--    end
--    self:_ace_old_notify_crop_destroyed(x, z)
-- end

-- function AceFarmerFieldComponent:_destroy_flood_listeners()
--    if self._flood_listeners then
--       for _, listener in pairs(self._flood_listeners) do
--          listener:destroy()
--       end
--    end
--    self._flood_listeners = {}
-- end

-- function AceFarmerFieldComponent:_destroy_flood_listener(id)
--    if self._flood_listeners[id] then
--       self._flood_listeners[id]:destroy()
--       self._flood_listeners[id] = nil
--    end
-- end

-- function AceFarmerFieldComponent:_create_flood_listeners()
--    self:_destroy_flood_listeners()

--    for x=1, self._sv.size.x do
-- 		for y=1, self._sv.size.y do
-- 			local dirt_plot = self._sv.contents[x][y]
-- 			if dirt_plot and dirt_plot.contents then
-- 				self:_create_flood_listener(dirt_plot.contents)
-- 			end
-- 		end
-- 	end
-- end

-- function AceFarmerFieldComponent:_create_flood_listener(crop)
--    local listener = self._flood_listeners[crop:get_id()]
--    if not listener then
--       self._flood_listeners[crop:get_id()] = radiant.events.listen(crop, 'stonehearth_ace:growing:flooded_changed', function(is_flooded)
--          if is_flooded then
--             self._sv.num_flooded = self._sv.num_flooded + 1
--          else
--             self._sv.num_flooded = self._sv.num_flooded - 1
--          end
--          self.__saved_variables:mark_changed()
--       end)
--    end
-- end

AceFarmerFieldComponent._ace_old_set_crop = FarmerFieldComponent.set_crop
function AceFarmerFieldComponent:set_crop(session, response, new_crop_id)
   local result = self:_ace_old_set_crop(session, response, new_crop_id)

   self:_cache_best_levels()
   self:_update_effective_humidity_level()

   return result
end

-- fertilizer preference is either a number (-1, 0, or 1) or a string (uri)
-- so we store it in a table similar to crafting ingredients material/uri
function AceFarmerFieldComponent:get_fertilizer_preference()
   return self._sv.fertilizer_preference
end

function AceFarmerFieldComponent:set_fertilizer_preference(preference)
   if preference.uri ~= self._sv.fertilizer_preference.uri or preference.quality ~= self._sv.fertilizer_preference.quality then
      -- uri outranks quality
      local uri = preference.uri
      local quality = not preference.uri and tonumber(preference.quality) or nil

      if uri ~= self._sv.fertilizer_preference.uri or quality ~= self._sv.fertilizer_preference.quality then
         if uri or quality then
            self._sv.fertilizer_preference = {
               uri = uri,
               quality = quality
            }
         else
            self._sv.fertilizer_preference = self:_get_default_fertilizer_preference()
         end

         self.__saved_variables:mark_changed()
         radiant.events.trigger(self, 'stonehearth_ace:farmer_field:fertilizer_preference_changed')
         if self._sv._fertilizable_layer then
            stonehearth.ai:reconsider_entity(self._sv._fertilizable_layer, 'fertilizer preference changed')
         end
      end
   end
end

function AceFarmerFieldComponent:_update_crop_fertilized(x, z, fertilized)
   if self._sv.contents == nil then
      --from 'notify_crop_destroyed' in base component:
      --Sigh the crop component hangs on to us instead of the entity
      --if this component is already destroyed, don't process the notification -yshan
      return
   end
   
   fertilized = fertilized or nil
   local dirt_plot = self._sv.contents[x][z]
   if dirt_plot then
      if fertilized and not dirt_plot.is_fertilized then
         self._sv.num_fertilized = self._sv.num_fertilized + 1
      elseif not fertilized and dirt_plot.is_fertilized then
         self._sv.num_fertilized = self._sv.num_fertilized - 1
      end
      dirt_plot.is_fertilized = fertilized
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_create_climate_listeners()
   -- periodically check sunlight and adjust growth rates accordingly
   if self._sunlight_timer then
      self:_destroy_climate_listeners()
   end

   if not self._sv.sunlight_level then
      self._sv.sunlight_level = 1
   end

   self._weather_listener = radiant.events.listen(radiant, 'stonehearth_ace:weather_state_started', function()
      self:_update_weather()
   end)
   self:_update_weather()

   self._season_listener = radiant.events.listen(radiant, 'stonehearth:seasons:changed', function()
      self:_update_season()
   end)
   self:_update_season()

   self._sunlight_timer = stonehearth.calendar:set_interval('farm sunlight check', SUNLIGHT_CHECK_TIME, function()
      self:_check_sky_visibility()
   end)
   self:_check_sky_visibility()
end

function AceFarmerFieldComponent:_destroy_climate_listeners()
   if self._sunlight_timer then
		self._sunlight_timer:destroy()
		self._sunlight_timer = nil
   end
   if self._weather_listener then
      self._weather_listener:destroy()
      self._weather_listener = nil
   end
   if self._season_listener then
      self._season_listener:destroy()
      self._season_listener = nil
   end
end

function AceFarmerFieldComponent:_update_weather()
   local weather = stonehearth.weather:get_current_weather()
   local sunlight = weather:get_sunlight()
   local humidity = weather:get_humidity()
   local changed = false

   if sunlight ~= self._weather_sunlight then
      self._weather_sunlight = sunlight
      changed = true
   end
   if humidity ~= self._weather_humidity then
      self._weather_humidity = humidity
      changed = true
   end

   if changed then
      self:_update_climate()
   end
end

function AceFarmerFieldComponent:_update_season()
   local season = stonehearth.seasons:get_current_season()
   local sunlight = season.sunlight or 1  -- current season is cached in the service, more trouble than it's worth to fix?
   local humidity = season.humidity or 0
   local changed = false

   if sunlight ~= self._season_sunlight then
      self._season_sunlight = sunlight
      changed = true
   end
   if humidity ~= self._season_humidity then
      self._season_humidity = humidity
      changed = true
   end

   if changed then
      self:_update_climate()
   end
end

function AceFarmerFieldComponent:_check_sky_visibility()
   -- check the center line of the farm along the z-axis
   local size = self._sv.size
   local x = math.floor(size.x / 2)
   local vis = 0
   for z = 0, size.y - 1 do
      vis = vis + stonehearth.terrain:get_sky_visibility(self._location + Point3(x, 2, z))
   end
   vis = vis / size.y

   if not self._sky_visibility or math.abs(vis - self._sky_visibility) > 0.001 then
      self._sky_visibility = vis
      self:_update_climate()
   end
end

function AceFarmerFieldComponent:_update_climate()
   if not self._sky_visibility or not self._biome_sunlight or not self._season_sunlight or not self._weather_sunlight then
      return
   end
   
   local changed = false
   local sunlight = math.floor(100 * self._sky_visibility * self._biome_sunlight * self._season_sunlight * self._weather_sunlight) / 100
   local humidity = math.floor(100 * (self._sv._water_level + self._biome_humidity + self._sky_visibility * (self._season_humidity + self._weather_humidity))) / 100

   if sunlight ~= self._sv.sunlight_level then
      self._sv.sunlight_level = sunlight
      changed = true
   end

   if humidity ~= self._sv.humidity_level then
      self._sv.humidity_level = humidity
      changed = true
   end

   if changed then
      self._sv._last_set_water_level = self._sv._water_level
      self:_update_effective_humidity_level()
      self:_set_growth_factors()
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_set_growth_factors()
   self._sv.growth_time_modifier = stonehearth.town:get_environmental_growth_time_modifier(
         self._sv.current_crop_details.preferred_climate,
         self._sv.humidity_level,
         self._sv.sunlight_level,
         self._sv.flooded and self._sv.current_crop_details.flood_period_multiplier)
   
   local size = self._sv.size
   local contents = self._sv.contents
   if contents then
      for x=1, size.x do
         for y=1, size.y do
            local dirt_plot = contents[x][y]
            if dirt_plot and dirt_plot.contents then
               dirt_plot.contents:add_component('stonehearth:growing'):set_environmental_growth_time_modifier(self._sv.growth_time_modifier)
            end
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function AceFarmerFieldComponent:_set_crops_flooded(flooded)
   local size = self._sv.size
   local contents = self._sv.contents
   if contents then
      for x=1, size.x do
         for y=1, size.y do
            local dirt_plot = contents[x][y]
            if dirt_plot and dirt_plot.contents then
               dirt_plot.contents:add_component('stonehearth:growing'):set_flooded(flooded)
            end
         end
      end
   end
end

function AceFarmerFieldComponent:_create_water_listener()
   local region = self._entity:get_component('region_collision_shape'):get_region():get()
   local water_region = region:extruded('x', 1, 1)
                              :extruded('z', 1, 1)
                              :extruded('y', 2, 0)
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_component:set_signal('farmer_field', water_region, {'water_volume'}, function(changes) self:_on_water_signal_changed(changes) end)
   self._sv.water_signal_region = water_region:duplicate()


   self._flood_signal = water_component:set_signal('farmer_field_flood', region, {'water_exists'}, function(changes) self:_on_flood_signal_changed(changes) end)

   self:_set_flooded(self._flood_signal:get_water_exists())
   self:_set_water_volume(self._water_signal:get_water_volume())
end

function AceFarmerFieldComponent:_set_water_volume(volume)
   if volume then
      -- we consider the normal ideal water volume to crop ratio to be a filled half perimeter around an 11x11 farm of 66 crops
      -- i.e., 24 water / 66 crops = 4/11
      -- we compare that to our current volume to crop ratio
      local ideal_ratio = 4/11
      local this_ratio = volume / (math.ceil(self._sv.size.x/2) * self._sv.size.y)
      self._sv._water_level = this_ratio / ideal_ratio
   else
      self._sv._water_level = 0
   end
   self.__saved_variables:mark_changed()

   -- if the water level only changed by a tiny bit, we don't want to recalculate water levels for everything
   -- once the change meets a particular threshold, go ahead and propogate
   local last_set = self._sv._last_set_water_level
   if last_set and math.abs(last_set - self._sv._water_level) < RECALCULATE_THRESHOLD then
      return
   end

   self:_update_climate()
end

function AceFarmerFieldComponent:_on_water_signal_changed(changes)
   local volume = changes.water_volume.value
   if not volume then
      return
   end
   
   self:_set_water_volume(volume)
end

function AceFarmerFieldComponent:_set_flooded(flooded)
   if flooded ~= self._sv.flooded then
      self._sv.flooded = flooded
      self.__saved_variables:mark_changed()
      self:_set_crops_flooded(flooded)
   end
end

function AceFarmerFieldComponent:_on_flood_signal_changed(changes)
   log:debug('_on_flood_signal_changed: %s', radiant.util.table_tostring(changes))
   local flooded = changes.water_exists.value
   if flooded == nil then
      return
   end
   
   self:_set_flooded(flooded)
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceFarmerFieldComponent:get_best_water_level()
	if self:_is_fallow() then
		return nil
	end
	
	return stonehearth.town:get_best_water_level_from_climate(self._sv.current_crop_details.preferred_climate)
end

function AceFarmerFieldComponent:get_best_light_level()
	if self:_is_fallow() then
		return nil
	end
	
	return stonehearth.town:get_best_light_level_from_climate(self._sv.current_crop_details.preferred_climate)
end

function AceFarmerFieldComponent:_cache_best_levels()
   self._best_water_level, self._next_water_level = self:get_best_water_level()
   self._best_light_level, self._next_light_level = self:get_best_light_level()
end

function AceFarmerFieldComponent:_update_effective_humidity_level()
   local levels = stonehearth.constants.farming.water_levels
   local relative_level = levels.NONE

   if self._best_water_level and self._sv.humidity_level >= self._best_water_level.min_level then
      if not self._next_water_level or self._sv.humidity_level < self._next_water_level.min_level then
         relative_level = levels.PLENTY
      else
         relative_level = levels.EXTRA
      end
   elseif self._sv.humidity_level > 0 then
      relative_level = levels.SOME
   end

   if self._sv.effective_humidity_level ~= relative_level then
      local size = self._sv.size
      local contents = self._sv.contents
      if relative_level == levels.EXTRA then
         -- randomly assign ~40% of furrow tiles (min of 1 per furrow column) to have puddles
         for x = 2, size.x, 2 do
            for i = 1, math.max(1, size.y * 0.4) do
               local y = rng:get_int(1, size.y)
               local plot = contents[x][y]
               if plot then
                  plot.overwatered_model = self:_get_overwatered_model()
               else
                  self._sv._queued_overwatered[x .. '|' .. y] = true
               end
            end
         end
      else
         self._sv._queued_overwatered = {}
         for x = 2, size.x, 2 do
            for _, plot in pairs(contents[x]) do
               plot.overwatered_model = nil
            end
         end
      end

      self._sv.effective_humidity_level = relative_level
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_get_overwatered_model()
   if not self._json then
      self._json = radiant.entities.get_json(self)
   end

   local model = self._json.overwatered_dirt
   if type(model) == 'table' then
      if #model > 0 then
         model = model[rng:get_int(1, #model)]
      else
         model = nil
      end
   end

   return model
end

AceFarmerFieldComponent._ace_old__on_destroy = FarmerFieldComponent._on_destroy
function AceFarmerFieldComponent:_on_destroy()
   self:_ace_old__on_destroy()
   
   radiant.entities.destroy_entity(self._sv._fertilizable_layer)
   self._sv._fertilizable_layer = nil

   --self:_destroy_flood_listeners()
   self:_destroy_climate_listeners()
end

AceFarmerFieldComponent._ace_old__reconsider_fields = FarmerFieldComponent._reconsider_fields
function AceFarmerFieldComponent:_reconsider_fields()
   for _, layer in ipairs({self._sv._soil_layer, self._sv._plantable_layer, self._sv._harvestable_layer, self._sv._fertilizable_layer}) do
      stonehearth.ai:reconsider_entity(layer, 'worker count changed')
   end
end

return AceFarmerFieldComponent
