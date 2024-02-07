local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('farmer_field')
local FarmerFieldComponent = require 'stonehearth.components.farmer_field.farmer_field_component'
local PatternCalculator = require 'stonehearth_ace.lib.pattern.pattern_calculator'
local resources_lib = require 'stonehearth_ace.lib.resources.resources_lib'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local constants = require 'stonehearth.constants'
local farming_constants = constants.farming

local FERTILIZER_MODEL_FAILSAFE = {
   -- defaults for unknown field types:
   model = 'stonehearth_ace/entities/farming/fertilize_applied/fertilize_applied.qb',
   offset = { x = 5, y = 1, z = 5},

   -- field-based defaults for known field types (will use above defaults if not specified):
   models = {
      farm = 'stonehearth_ace/entities/farming/fertilize_applied/fertilize_applied.qb',
   },
   offsets = {
      farm = { x = 5, y = 1, z = 5},
   }
}

local AceFarmerFieldComponent = class()

AceFarmerFieldComponent._ace_old_restore = FarmerFieldComponent.restore
function AceFarmerFieldComponent:restore()
   self._is_restore = true
   self._sv.water_level = nil
   self._sv.last_set_water_level = nil
   if not self._sv.rotation then
      self._sv.rotation = 0
   end
   if not self._sv.max_num_crops then
      self._sv.max_num_crops = math.ceil(self._sv.size.x / 2) * self._sv.size.y
   end
   
   self:_ace_old_restore()

   -- if this is an old farm that doesn't have full details, reload the details
   if self._sv.current_crop_details and not self._sv.current_crop_details.flood_period_multiplier then
      self._sv.current_crop_details = stonehearth.farming:get_crop_details(self._sv.current_crop_alias)
      self.__saved_variables:mark_changed()
   end

   self:_cache_best_levels()
end

AceFarmerFieldComponent._ace_old_activate = FarmerFieldComponent.activate
function AceFarmerFieldComponent:activate()
   self._json = radiant.entities.get_json(self)
   self:_ace_old_activate()
end

function AceFarmerFieldComponent:post_activate()
   local biome = stonehearth.world_generation:get_biome()
   self._biome_sunlight = biome.sunlight or 1
   self._biome_humidity = biome.humidity or 0
   self._biome_elevation_modifiers = biome.farm_elevation_modifiers or {}
   
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
   if not self._sv._queued_overwatered then
      self._sv._queued_overwatered = {}
   end

   self._water_recalculate_threshold = stonehearth.constants.farming.WATER_RECALCULATE_THRESHOLD

   self:_ensure_crop_counts()
   self:_ensure_fertilize_layer()

   self._post_harvest_crop_listeners = {}
   if self._is_restore then
      self:_load_field_type()
      self:_cache_biome_elevation_levels()
      self:_create_listeners()
      self:_consider_remove_from_town_patrol()
   end
end

function AceFarmerFieldComponent:_create_listeners()
   if not self._is_suspended then
      self:_create_water_listener()
      self:_create_climate_listeners()
      self:_create_all_post_harvest_crop_listeners()
      self:_create_fertilize_task()
   end
end

function AceFarmerFieldComponent:_consider_remove_from_town_patrol()
   if self:get_field_type() == 'decorative_flowers' then
      stonehearth.town_patrol:_remove_from_patrol_list(self._entity:get_id())
   end
end

function AceFarmerFieldComponent:set_harvest_enabled(enabled)
   if enabled ~= self._sv.harvest_enabled then
      self._sv.harvest_enabled = enabled
      self.__saved_variables:mark_changed()
      stonehearth.ai:reconsider_entity(self._sv._harvestable_layer, 'field changed harvest enabled state')

      -- if there are post_harvest entities (e.g., evolve rn/rrn crops), toggle the harvest requests accordingly
      local size = self._sv.size
      local contents = self._sv.contents
      if contents then
         for x = 1, size.x do
            for y = 1, size.y do
               local dirt_plot = contents[x][y]
               if dirt_plot and dirt_plot.post_harvest_contents then
                  if enabled then
                     resources_lib.request_auto_harvest(dirt_plot.post_harvest_contents)
                  else
                     resources_lib.cancel_harvest_request(dirt_plot.post_harvest_contents)
                  end
               end
            end
         end
      end
   end
end

function AceFarmerFieldComponent:suspend_entity()
   self._is_suspended = true
   self:_destroy_listeners()
end

function AceFarmerFieldComponent:continue_entity()
   self._is_suspended = nil
   self:_create_listeners()
end

function AceFarmerFieldComponent:is_harvest_enabled()
   return self._sv.harvest_enabled
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
               dirt_plot.fertilizer_model = dirt_plot.fertilizer_model or FERTILIZER_MODEL_FAILSAFE
               num_fertilized = num_fertilized + 1
            end
         end
      end

      self._sv.num_fertilized = num_fertilized
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_ensure_fertilize_layer()
   if not self._sv._fertilizable_layer then
      self._sv._fertilizable_layer = self:_create_field_layer('stonehearth_ace:farmer:field_layer:fertilizable')
      --self.__saved_variables:mark_changed()
   end
   if self._is_restore then
      self._sv._fertilizable_layer:get_component('destination')
                     :set_reserved(_radiant.sim.alloc_region3()) -- xxx: clear the existing one from cpp land!
                     :set_auto_update_adjacent(true)
   end

   table.insert(self._field_listeners, radiant.events.listen(self._sv._fertilizable_layer, 'radiant:entity:pre_destroy', self, self._on_field_layer_destroyed))
end

function AceFarmerFieldComponent:_ensure_fertilizer_preference()
   if not self._sv.fertilizer_preference then
      self._sv.fertilizer_preference = self:_get_default_fertilizer_preference()
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_get_default_fertilizer_preference()
   if not self._sv.allow_fertilizing then
      return { quality = 0 }
   end
   
   local player_id = self._entity:get_player_id()
   local default = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'default_fertilizer', '1')
   return self:_get_fertilizer_preference(default)
end

function AceFarmerFieldComponent:_get_fertilizer_preference(preference)
   if tonumber(preference) then
      return { quality = tonumber(preference) }
   else
      return { uri = preference }
   end
end

function AceFarmerFieldComponent:get_contents()
   return self._sv.contents
end

function AceFarmerFieldComponent:get_rotation()
   return self._sv.rotation
end

function AceFarmerFieldComponent:get_field_type()
	return self._sv.field_type
end

function AceFarmerFieldComponent:get_current_crop_alias()
   if not self:_is_fallow() then
      return self._sv.current_crop_alias
   end
end

function AceFarmerFieldComponent:_load_field_type()
   self._field_type_data = stonehearth.farming:get_field_type(self._sv.field_type or 'farm') or {}
   local pattern = self._field_type_data.pattern or farming_constants.DEFAULT_PATTERN
   local border = self._field_type_data.border or 0
   self._pattern_calculator = PatternCalculator(pattern, math.max(self._sv.size.x, self._sv.size.y), border)
      :set_rotation(self._sv.rotation):set_size(self._sv.size.x, self._sv.size.y)

   self._sv.allow_disable_harvest = self._field_type_data.allow_disable_harvest
   self._sv.allow_fertilizing = self._field_type_data.allow_fertilizing ~= false

   self._dirt_models = self._field_type_data.dirt_models and self._json.dirt_models[self._field_type_data.dirt_models] or self._json.dirt_models.default
   
   self:_ensure_fertilizer_preference()
end

AceFarmerFieldComponent._ace_old_on_field_created = FarmerFieldComponent.on_field_created
function AceFarmerFieldComponent:on_field_created(town, size, field_type, rotation)
   self:_ace_old_on_field_created(town, size)

   radiant.terrain.place_entity(self._sv._fertilizable_layer, self._location)
   self._sv._queued_overwatered = {}

   -- change the soil layer to only fill in the spots this field type requires
   self._sv.field_type = field_type
   self._sv.rotation = rotation
   -- for _, layer in ipairs(self:_get_field_layers()) do
   --    radiant.entities.turn_to(layer, rotation * 90)
   -- end

   self:_load_field_type()
   if self._sv.harvest_enabled == nil then
      self._sv.harvest_enabled = not self._field_type_data.default_disable_harvest
   end

   local soil_layer = self._sv._soil_layer
   local soil_layer_region = soil_layer:get_component('destination'):get_region()
   local max_num_crops = 0
   soil_layer_region:modify(function(cursor)
      for x = 1, size.x do
         for y = 1, size.y do
            local location_type = self._pattern_calculator:get_location_type(x, y) or farming_constants.location_types.EMPTY
            if location_type == farming_constants.location_types.EMPTY then
               cursor:subtract_point(Point3(x - 1, 0, y - 1))
            elseif location_type == farming_constants.location_types.CROP then
               max_num_crops = max_num_crops + 1
            end
         end
      end
   end)

   self._sv.max_num_crops = math.max(1, max_num_crops)

   self:_cache_biome_elevation_levels()
   self:_create_water_listener()
   self:_create_climate_listeners()
   self:_check_sky_visibility()
   self:_consider_remove_from_town_patrol()
end

function AceFarmerFieldComponent:_is_location_furrow(x, y)
   return self._pattern_calculator:get_location_type(x, y) == farming_constants.location_types.FURROW or false
end

function AceFarmerFieldComponent:notify_till_location_finished(location)
   local offset = location - radiant.entities.get_world_grid_location(self._entity)
   local x = offset.x + 1
   local y = offset.z + 1
   local is_furrow = self:_is_location_furrow(x, y)
   local dirt_plot = {
      is_furrow = is_furrow,
      x = x,
      y = y
   }

   --self:_create_tilled_dirt(location, offset.x + 1, offset.z + 1)
   self._sv.contents[x][y] = dirt_plot
   local local_fertility = rng:get_gaussian(self._sv.general_fertility, stonehearth.constants.soil_fertility.VARIATION)
   --local dirt_plot_component = dirt_plot:get_component('stonehearth:dirt_plot')

   -- Have to update the soil model to make the plot visible.
   --dirt_plot_component:update_soil_model(local_fertility, 50)

   local soil_layer = self._sv._soil_layer
   local soil_layer_region = soil_layer:get_component('destination')
                                :get_region()

   soil_layer_region:modify(function(cursor)
      cursor:subtract_point(offset)
   end)

   -- Add the region to the plantable region if necessary
   self:_try_mark_for_plant(dirt_plot)

   
   local key = x .. '|' .. y
   if self._sv._queued_overwatered[key] then
      dirt_plot.overwatered_model = self:_get_overwatered_model()
      self._sv._queued_overwatered[key] = nil
   end

   self.__saved_variables:mark_changed()
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
   self:_ensure_fertilize_task()
end

function AceFarmerFieldComponent:_create_all_post_harvest_crop_listeners()
   local contents = self._sv.contents
   local size = self._sv.size
   if contents then
      for x = 1, size.x do
         for y = 1, size.y do
            local dirt_plot = contents[x][y]
            if dirt_plot then
               self:_create_post_harvest_crop_listeners(dirt_plot)
            end
         end
      end
   end
end

function AceFarmerFieldComponent:update_post_harvest_crop(x, z, crop)
   local dirt_plot = self._sv.contents and self._sv.contents[x][z]
   --log:debug('updating post-harvest crop: %s for plot %s', crop, radiant.util.table_tostring(dirt_plot))
   if dirt_plot then
      -- set up the listener
      self:_destroy_post_harvest_crop_listeners(dirt_plot)
      dirt_plot.post_harvest_contents = crop
      self:_create_post_harvest_crop_listeners(dirt_plot)
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_create_post_harvest_crop_listeners(dirt_plot)
   local entity = dirt_plot.post_harvest_contents

   if entity and not self._post_harvest_crop_listeners[dirt_plot] then
      local on_removed = function()
         dirt_plot.post_harvest_contents = nil
         self:_destroy_post_harvest_crop_listeners(dirt_plot)
         self:_try_mark_for_plant(dirt_plot)
      end

      local listeners = {
         -- if the entity is destroyed
         pre_destroy = radiant.events.listen_once(entity, 'radiant:entity:pre_destroy', on_removed),
         -- if the entity's parent changes and it's no longer in the world (e.g., picked up or iconified)
         parent_changed = radiant.events.listen(entity, 'radiant:mob:parent_changed', function()
            if radiant.entities.get_world_grid_location(entity) == nil then
               entity:remove_component('stonehearth:crop')
               local output = entity:get_component('stonehearth_ace:output')
               if output then
                  output:set_parent_output()
               end
               on_removed()
            end
         end)
      }
      self._post_harvest_crop_listeners[dirt_plot] = listeners
   end
end

function AceFarmerFieldComponent:_destroy_all_post_harvest_crop_listeners()
   -- on restore, a suspended town can have farmer fields where this table hasn't been created yet
   if not self._post_harvest_crop_listeners then
      return
   end

   for _, listeners in pairs(self._post_harvest_crop_listeners) do
      for _, listener in pairs(listeners) do
         listener:destroy()
      end
   end
   self._post_harvest_crop_listeners = {}
end

function AceFarmerFieldComponent:_destroy_post_harvest_crop_listeners(dirt_plot)
   local listeners = self._post_harvest_crop_listeners[dirt_plot]
   if listeners then
      for _, listener in pairs(listeners) do
         listener:destroy()
      end
      self._post_harvest_crop_listeners[dirt_plot] = nil
   end
end

function AceFarmerFieldComponent:_replace_crop_with_post_harvest(dirt_plot, product, auto_harvest_type)
   local crop_comp = dirt_plot.contents:get_component('stonehearth:crop')
   local x, z = crop_comp:get_field_offset()
   local iconic = true

   if product then
      if auto_harvest_type == 'place' then
         iconic = false
         product = entity_forms_lib.get_root_entity(product) or product

         dirt_plot.post_harvest_contents = product
         product:add_component('stonehearth:crop'):set_field(self, x, z)
         product:add_component('stonehearth_ace:output'):set_parent_output(self._entity)
         -- when the crop is destroyed, it reduces the crop count by one, so offset that by adding one
         self._sv.num_crops = self._sv.num_crops + 1
      end
   end

   radiant.entities.kill_entity(dirt_plot.contents)
   dirt_plot.contents = nil
   if product then
      radiant.terrain.place_entity_at_exact_location(product, self._location + Point3(x - 1, 0, z - 1), {force_iconic = iconic})
      self:_create_post_harvest_crop_listeners(dirt_plot)
   end

   self.__saved_variables:mark_changed()

   return product
end

function AceFarmerFieldComponent:_destroy_plot_contents(dirt_plot)
   if dirt_plot.contents then
      radiant.entities.kill_entity(dirt_plot.contents)
      dirt_plot.contents = nil
   end

   if dirt_plot.post_harvest_contents then
      radiant.entities.kill_entity(dirt_plot.post_harvest_contents)
   end
end

function AceFarmerFieldComponent:auto_harvest_crop(auto_harvest_type, x, z)
   -- automatically harvest the crop; if the type is 'place', place it 
   self:_update_crop_fertilized(x, z, false)
   local dirt_plot = self._sv.contents and self._sv.contents[x][z]
   if dirt_plot and dirt_plot.contents then
      local product_uri = dirt_plot.contents:get_component('stonehearth:crop'):get_product()
      local product = product_uri and radiant.entities.create_entity(product_uri, { owner = self._entity })
      self:_replace_crop_with_post_harvest(dirt_plot, product, auto_harvest_type)
   end
end

-- try to harvest a crop; used by harvest ai, auto-harvest/place (crop settings), and instructed harvests
function AceFarmerFieldComponent:try_harvest_crop(harvester, x, z, num_stacks, auto_harvest_type)
   --log:debug('%s try_harvest_crop(%s, %s, %s, %s, %s)', self._entity, tostring(harvester), tostring(x), tostring(z), tostring(num_stacks), tostring(auto_harvest_type))
   local dirt_plot = self._sv.contents and self._sv.contents[x][z]
   local crop = dirt_plot and dirt_plot.contents
   if crop then
      num_stacks = num_stacks or 1
      local origin = self._location + Point3(x - 1, 0, z - 1)
      local crop_comp = crop:get_component('stonehearth:crop')
      if not crop_comp:is_harvestable() then
         return false
      end

      local primary_item, other_items = crop_comp:get_harvest_items(harvester, num_stacks)
      --log:debug('harvest %s items: %s, %s', crop, tostring(primary_item), radiant.util.table_tostring(other_items))

      -- try to output the items
      -- if there's a harvester entity or an auto_harvest_type specified, the harvesting will go through and spill if necessary
      -- if there's a harvester entity, they will pick up the primary item (or add stacks to the one they're carrying)
      -- if an auto_harvest_type is specified, the primary item will be placed in the exact crop location
      -- if no harvester or auto_harvest_type, stick the primary item into the other items and try to output them all without spilling
      --    if no items are successfully output, cancel the harvest
      if not harvester and not auto_harvest_type and primary_item then
         other_items[primary_item:get_id()] = primary_item
         primary_item = nil
      end
      local items
      if next(other_items) then
         local options = {
            inputs = harvester,
            output = crop,
            spill_fail_items = harvester or auto_harvest_type,
         }
         items = radiant.entities.output_spawned_items(other_items, origin, 0, 2, options)
         --log:debug('output result: %s', radiant.util.table_tostring(items))
      end

      if not harvester and not auto_harvest_type and (not items or not next(items.succeeded)) then
         return false
      end

      if primary_item then
         if harvester then
            local carrying = radiant.entities.get_carrying(harvester)
            if carrying then
               if carrying:get_uri() == primary_item:get_uri() then
                  local stacks_component = carrying:get_component('stonehearth:stacks')
                  if stacks_component then
                     -- if new item is a higher quality, add stacks from carrying to new primary item and replace carrying with it
                     if radiant.entities.get_item_quality(carrying) < radiant.entities.get_item_quality(primary_item) then
                        primary_item:add_component('stonehearth:stacks'):add_stack(stacks_component:get_stacks())
                        self:_replace_harvester_carrying(harvester, primary_item)
                     else
                        -- if it's the same quality, just add the stacks to the carrying item
                        carrying:add_component('stonehearth:stacks'):add_stack(primary_item:get_component('stonehearth:stacks'):get_stacks())
                        radiant.entities.destroy_entity(primary_item)
                        primary_item = nil
                     end
                  end
               else
                  self:_replace_harvester_carrying(harvester, primary_item)
               end
            else
               self:_replace_harvester_carrying(harvester, primary_item)
            end
         end
      end

      local stage = crop_comp:get_post_harvest_stage()
      local crop_uri = self:get_current_crop_alias()
      if stage and crop:get_uri() == crop_uri then
         crop:get_component('stonehearth:growing'):set_growth_stage(stage)
         self:_update_crop_fertilized(x, z, false)
      else
         self:_replace_crop_with_post_harvest(dirt_plot, not harvester and primary_item, auto_harvest_type)
      end

      return true
   end
end

function AceFarmerFieldComponent:_replace_harvester_carrying(harvester, new_carrying)
   local carrying = radiant.entities.remove_carrying(harvester)
   if carrying then
      radiant.entities.destroy_entity(carrying)
   end

   radiant.entities.pickup_item(harvester, new_carrying)
   -- newly harvested drops go into your inventory immediately unless your inventory is full
   stonehearth.inventory:get_inventory(radiant.entities.get_work_player_id(harvester))
                           :add_item_if_not_full(new_carrying)
end

AceFarmerFieldComponent._ace_old__try_mark_for_plant = FarmerFieldComponent._try_mark_for_plant
function AceFarmerFieldComponent:_try_mark_for_plant(dirt_plot)
   local existing_crop = dirt_plot.contents or dirt_plot.post_harvest_contents
   if existing_crop then
      local crop_comp = existing_crop:get_component('stonehearth:crop')
      if crop_comp and crop_comp:get_destroy_on_crop_change() then
         self:_destroy_plot_contents(dirt_plot)
      end
   end
   
   if not dirt_plot.post_harvest_contents then
      self:_ace_old__try_mark_for_plant(dirt_plot)
   end
end

AceFarmerFieldComponent._ace_old_notify_crop_harvestable = FarmerFieldComponent.notify_crop_harvestable
function AceFarmerFieldComponent:notify_crop_harvestable(x, z)
   self:_ace_old_notify_crop_harvestable(x, z)
   self:_remove_from_fertilizable(Point3(x - 1, 0, z - 1))
   radiant.events.trigger(self._entity, 'stonehearth:farmer_field:crop_harvestable', {
      crop = self._sv.contents[x][z].contents
   })
end

function AceFarmerFieldComponent:notify_crop_fertilized(location, fertilizer_model)
   local p = Point3(location.x - self._location.x, 0, location.z - self._location.z)
   self:_remove_from_fertilizable(p)
   self:_update_crop_fertilized(p.x + 1, p.z + 1, true, fertilizer_model)
end

function AceFarmerFieldComponent:_remove_from_fertilizable(location)
   local fertilizable_layer = self._sv._fertilizable_layer
   local fertilizable_layer_region = fertilizable_layer:get_component('destination'):get_region()
   fertilizable_layer_region:modify(function(cursor)
      cursor:subtract_point(location)
   end)
   self:_ensure_fertilize_task()
end

function AceFarmerFieldComponent:_remove_from_harvestable(x, z)
   local harvestable_layer = self._sv._harvestable_layer
   local harvestable_layer_region = harvestable_layer:get_component('destination')
                                       :get_region()
   harvestable_layer_region:modify(function(cursor)
      cursor:subtract_point(Point3(x - 1, 0, z - 1))
   end)
end

function AceFarmerFieldComponent:notify_crop_unharvestable(x, z)
   -- if we're just setting it to an earlier stage, remove it from harvestable layer
   self:_remove_from_harvestable(x, z)
end

AceFarmerFieldComponent._ace_old_notify_crop_destroyed = FarmerFieldComponent.notify_crop_destroyed
function AceFarmerFieldComponent:notify_crop_destroyed(x, z)
   self:_ace_old_notify_crop_destroyed(x, z)
   self:_update_crop_fertilized(x, z, false)
end

AceFarmerFieldComponent._ace_old_plant_crop_at = FarmerFieldComponent.plant_crop_at
function AceFarmerFieldComponent:plant_crop_at(x_offset, z_offset)
   local crop = self:_ace_old_plant_crop_at(x_offset, z_offset)

   if crop then
      radiant.entities.turn_to(crop, self._sv.rotation * 90)

      local growing_comp = crop:add_component('stonehearth:growing')
      if growing_comp then
         growing_comp:set_environmental_growth_time_modifier(self._sv.growth_time_modifier)
         growing_comp:set_flooded(self._sv.flooded)
      end
      crop:get_component('stonehearth:crop'):set_destroy_on_crop_change(self._sv.current_crop_details.destroy_on_crop_change)

      crop:add_component('stonehearth_ace:output'):set_parent_output(self._entity)
   end
end

function AceFarmerFieldComponent:set_crop(session, response, new_crop_id)
   self._sv.current_crop_details = stonehearth.farming:get_crop_details(new_crop_id)
   self._sv.has_set_crop = true

   if self._sv.current_crop_alias ~= new_crop_id then
      self._sv.current_crop_alias = new_crop_id
      self:_update_plantable_layer()

      if self._sv.current_crop_details and self._sv.current_crop_details.force_fertilizer_setting then
         self._sv.fertilizer_preference = self:_get_fertilizer_preference(self._sv.current_crop_details.force_fertilizer_setting)
      end

      self.__saved_variables:mark_changed()
   end

   self:_cache_best_levels()
   self:_update_effective_humidity_level()
   self:_set_growth_factors()

   return true
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
         self:_create_fertilize_task()

         -- if self._sv._fertilizable_layer then
         --    stonehearth.ai:reconsider_entity(self._sv._fertilizable_layer, 'fertilizer preference changed')
         -- end
      end
   end
end

function AceFarmerFieldComponent:_update_crop_fertilized(x, z, fertilized, fertilizer_model)
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
      dirt_plot.fertilizer_model = fertilized and self:_get_fertilizer_model_data(fertilizer_model) or nil
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_get_fertilizer_model_data(fertilizer_model)
   if not fertilizer_model then
      return FERTILIZER_MODEL_FAILSAFE
   end
   
   -- determine the actual model data based on this field type
   local farm_type = self._sv.field_type or 'farm'
   local model_data = {
      model = fertilizer_model.models and fertilizer_model.models[farm_type] or
            fertilizer_model.model or FERTILIZER_MODEL_FAILSAFE.models[farm_type] or FERTILIZER_MODEL_FAILSAFE.model,
      offset = fertilizer_model.offsets and fertilizer_model.offsets[farm_type] or
            fertilizer_model.offset or FERTILIZER_MODEL_FAILSAFE.offsets[farm_type] or FERTILIZER_MODEL_FAILSAFE.offset,
   }
   return model_data
end

function AceFarmerFieldComponent:_create_climate_listeners()
   -- periodically check sunlight and adjust growth rates accordingly
   self:_destroy_climate_listeners()

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

   self._sunlight_timer = stonehearth.calendar:set_interval('farm sunlight check', stonehearth.constants.farming.SUNLIGHT_CHECK_FREQUENCY, function()
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
   local is_frozen = weather:is_frozen()
   local changed = false

   if sunlight ~= self._weather_sunlight then
      self._weather_sunlight = sunlight
      changed = true
   end
   if humidity ~= self._weather_humidity then
      self._weather_humidity = humidity
      changed = true
   end
   if is_frozen ~= self._weather_frozen then
      self._weather_frozen = is_frozen
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
      vis = vis + stonehearth.terrain:get_sky_visibility(self._location + Point3(x, 2, z), nil, function(entity)
            return entity:get_component('stonehearth:crop') ~= nil
         end)
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
   local raw_sunlight = self._sky_visibility * self._biome_sunlight * self._season_sunlight * self._weather_sunlight
   local sunlight = math.floor(100 * raw_sunlight * self._light_elevation_modifier) / 100

   local raw_humidity = self._sv._water_level + self._biome_humidity + self._sky_visibility * (self._season_humidity + self._weather_humidity)
   local humidity = math.floor(100 * raw_humidity * self._humidity_elevation_modifier) / 100
   local frozen = self._weather_frozen

   if sunlight ~= self._sv.sunlight_level then
      self._sv.sunlight_level = sunlight
      changed = true
   end

   if humidity ~= self._sv.humidity_level then
      self._sv.humidity_level = humidity
      changed = true
   end

   if frozen ~= self._sv.frozen then
      self._sv.frozen = frozen
      self.__saved_variables:mark_changed()
   end

   if changed then
      self._sv._last_set_water_level = self._sv._water_level
      self:_update_effective_humidity_level()
      self:_set_growth_factors()
   end
end

function AceFarmerFieldComponent:_set_growth_factors()
   self._sv.growth_time_modifier = stonehearth.town:get_environmental_growth_time_modifier(
         self._sv.current_crop_details.preferred_climate,
         self._sv.humidity_level,
         self._sv.sunlight_level,
         self._sv.flooded and self._sv.current_crop_details.flood_period_multiplier,
         self._sv.frozen and self._sv.current_crop_details.frozen_period_multiplier)
   -- log:debug('setting growth factors: %s, %s, %s, %s, %s: %s', self._sv.current_crop_details.preferred_climate, self._sv.humidity_level, self._sv.sunlight_level,
   --    self._sv.flooded, self._sv.frozen, self._sv.growth_time_modifier)

   local size = self._sv.size
   local contents = self._sv.contents
   if contents then
      for x=1, size.x do
         for y=1, size.y do
            local dirt_plot = contents[x][y]
            if dirt_plot and dirt_plot.contents then
               if dirt_plot.contents:get_uri() == self._sv.current_crop_alias then
                  dirt_plot.contents:add_component('stonehearth:growing'):set_environmental_growth_time_modifier(self._sv.growth_time_modifier)
               end
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
   local region = self._entity:get_component('region_collision_shape'):get_region():get():duplicate()
   local water_region = region:extruded('x', 1, 1)
                              :extruded('z', 1, 1)
                              :extruded('y', 2, 0)
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_component:set_signal('farmer_field', water_region, {'water_volume'}, function(changes) self:_on_water_signal_changed(changes) end)
   self._sv.water_signal_region = water_region
   self._flood_signal = water_component:set_signal('farmer_field_flood', region, {'water_exists'}, function(changes) self:_on_flood_signal_changed(changes) end)

   self:_set_flooded(self._flood_signal:get_water_exists())
   self:_set_water_volume(self._water_signal:get_water_volume())
end

function AceFarmerFieldComponent:_destroy_water_listener()
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   if self._water_signal then
      water_component:remove_signal('farmer_field')
   end
   if self._flood_signal then
      water_component:remove_signal('farmer_field_flood')
   end
end

function AceFarmerFieldComponent:_set_water_volume(volume)
   if volume then
      -- we consider the normal ideal water volume to crop ratio to be a filled half perimeter around an 11x11 farm of 66 crops
      -- i.e., 24 water / 66 crops = 4/11
      -- we compare that to our current volume to crop ratio
      local ideal_ratio = 4/11
      -- account for rotation

      local this_ratio = volume / (self._sv.max_num_crops or 66)
      self._sv._water_level = this_ratio / ideal_ratio
   else
      self._sv._water_level = 0
   end
   --self.__saved_variables:mark_changed()

   -- if the water level only changed by a tiny bit, we don't want to recalculate water levels for everything
   -- once the change meets a particular threshold, go ahead and propogate
   local last_set = self._sv._last_set_water_level
   if last_set and math.abs(last_set - self._sv._water_level) < self._water_recalculate_threshold then
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

function AceFarmerFieldComponent:_set_frozen(frozen)
   if frozen ~= self._sv.frozen then
      self._sv.frozen = frozen
      self.__saved_variables:mark_changed()
   end
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceFarmerFieldComponent:get_best_water_level()
	return stonehearth.town:get_best_water_level_from_climate(not self:_is_fallow() and self._sv.current_crop_details.preferred_climate)
end

function AceFarmerFieldComponent:get_best_light_level()
	return stonehearth.town:get_best_light_level_from_climate(not self:_is_fallow() and self._sv.current_crop_details.preferred_climate)
end

function AceFarmerFieldComponent:get_elevation_modifiers()
   if self._location then
      local y = self._location.y
      log:debug('%s caching elevation modifiers for %s', self._entity, y)
      return self:_get_elevation_modifier('humidity', y), self:_get_elevation_modifier('sunlight', y)
   end

   return 1, 1
end

function AceFarmerFieldComponent:_get_elevation_modifier(mod_type, elevation)
   local best = 1
   local modifiers = self._biome_elevation_modifiers[mod_type]
   if modifiers then
      for _, data in ipairs(modifiers) do
         if elevation > data.elevation then
            break
         end
         best = data.multiplier
      end
   end

   return best
end

function AceFarmerFieldComponent:_cache_best_levels()
   self._best_water_level, self._next_water_level = self:get_best_water_level()
   self._best_light_level, self._next_light_level = self:get_best_light_level()
end

function AceFarmerFieldComponent:_cache_biome_elevation_levels()
   self._humidity_elevation_modifier, self._light_elevation_modifier = self:get_elevation_modifiers()
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
         -- randomly assign ~20% of tiles to have puddles (only allowed in furrows)
         local num_desired = size.x * size.y * 0.2
         -- cap the number of attempts in case this field layout just doesn't allow for that many
         for i = 1, num_desired * 5 do
            local x = rng:get_int(1, size.x)
            local y = rng:get_int(1, size.y)
            if self:_is_location_furrow(x, y) then
               local plot = contents[x][y]
               if plot then
                  plot.overwatered_model = self:_get_overwatered_model()
               else
                  self._sv._queued_overwatered[x .. '|' .. y] = true
               end

               num_desired = num_desired - 1
               if num_desired <= 0 then
                  break
               end
            end
         end
      else
         self._sv._queued_overwatered = {}
         for _, row in pairs(contents) do
            for _, plot in pairs(row) do
               plot.overwatered_model = nil
            end
         end
      end

      self._sv.effective_humidity_level = relative_level
      self.__saved_variables:mark_changed()
   end
end

function AceFarmerFieldComponent:_get_overwatered_model()
   local model = self._dirt_models.overwatered_dirt
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
   self:_destroy_post_harvest_crops()

   self:_ace_old__on_destroy()
   
   radiant.entities.destroy_entity(self._sv._fertilizable_layer)
   self._sv._fertilizable_layer = nil

   self:_destroy_listeners()
   self:_destroy_fertilize_task()
end

function AceFarmerFieldComponent:_destroy_listeners()
   --self:_destroy_flood_listeners()
   self:_destroy_water_listener()
   self:_destroy_climate_listeners()
   self:_destroy_all_post_harvest_crop_listeners()
end

-- go through post_harvest contents:
-- destroy if not RN, remove crop component if they are
function AceFarmerFieldComponent:_destroy_post_harvest_crops()
   local contents = self._sv.contents
   if contents then
      for x=1, self._sv.size.x do
         for y=1, self._sv.size.y do
            local dirt_plot = contents[x][y]
            local post_harvest_contents = dirt_plot and dirt_plot.post_harvest_contents
            if post_harvest_contents then
               -- if it's an RRN, it won't have commands for moving/undeploying, so we need to destroy it
               local resource_node = post_harvest_contents:get_component('stonehearth:resource_node')
               if resource_node then
                  local crop = post_harvest_contents:get_component('stonehearth:crop')
                  if crop then
                     crop:set_field()
                     post_harvest_contents:remove_component('stonehearth:crop')
                  end
                  local output = post_harvest_contents:get_component('stonehearth_ace:output')
                  if output then
                     output:set_parent_output()
                  end

                  -- also trigger a harvest request for them
                  resource_node:request_harvest(radiant.entities.get_player_id(self._entity))
               else
                  radiant.entities.destroy_entity(post_harvest_contents)
               end
               dirt_plot.post_harvest_contents = nil
            end
         end
      end
   end
end

function AceFarmerFieldComponent:_get_field_layers()
   return {self._sv._soil_layer, self._sv._plantable_layer, self._sv._harvestable_layer, self._sv._fertilizable_layer}
end

AceFarmerFieldComponent._ace_old__reconsider_fields = FarmerFieldComponent._reconsider_fields
function AceFarmerFieldComponent:_reconsider_fields()
   for _, layer in ipairs(self:_get_field_layers()) do
      stonehearth.ai:reconsider_entity(layer, 'worker count changed')
   end
end

function AceFarmerFieldComponent:_get_fertilizer_filter_and_rater()
   local owner = radiant.entities.get_player_id(self._entity)
   local preference = self:get_fertilizer_preference()

   if preference.uri then
      local uri = preference.uri

      local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilizer:uri', uri .. '|' .. tostring(owner), function(item)
            if owner and owner ~= item:get_player_id() then
               return false
            end
            
            local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
            if not data then
               return false
            end

            return uri == item:get_uri()
         end)
      
      return filter_fn
   elseif preference.quality ~= 0 then
      local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:fertilizer:quality', owner, function(item)
            if owner and owner ~= item:get_player_id() then
               return false
            end
            
            local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
            if not data then
               return false
            end

            return data.ilevel ~= nil
         end)
      
      local quality_range = stonehearth.farming:get_fertilizer_quality_range()
      local rating_fn
      if preference.quality > 0 then
         rating_fn = function(item)
            local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
            local rating = (data.ilevel - quality_range.min) / quality_range.range
            return rating
         end
      else
         rating_fn = function(item)
            local data = radiant.entities.get_entity_data(item, 'stonehearth_ace:fertilizer')
            local rating = (quality_range.max - data.ilevel) / quality_range.range
            return rating
         end
      end

      return filter_fn, rating_fn
   end
end

function AceFarmerFieldComponent:_destroy_fertilize_task()
   if self._fertilize_task then
      self._fertilize_task:destroy()
      self._fertilize_task = nil
   end
end

function AceFarmerFieldComponent:_is_any_plot_fertilizable()
   local fertilizable_layer = self._sv._fertilizable_layer
   return fertilizable_layer and fertilizable_layer:get_component('destination'):get_region():get():get_area() > 0
end

function AceFarmerFieldComponent:_ensure_fertilize_task()
   if not self:_is_any_plot_fertilizable() then
      self:_destroy_fertilize_task()
   elseif not self._fertilize_task then
      self:_create_fertilize_task(true)
   end
end

function AceFarmerFieldComponent:_create_fertilize_task(skip_is_any_plot_check)
   self:_destroy_fertilize_task()

   if not skip_is_any_plot_check and not self:_is_any_plot_fertilizable() then
      return
   end
   
   local town = stonehearth.town:get_town(self._entity)
   local fertilizer_filter_fn, fertilizer_rating_fn = self:_get_fertilizer_filter_and_rater()

   if fertilizer_filter_fn then
      local fertilize_task = town:create_task_for_group(
         'stonehearth:task_groups:farming',
         'stonehearth_ace:fertilize_field',
         {
            field = self._sv._fertilizable_layer,
            fertilizer_filter_fn = fertilizer_filter_fn,
            fertilizer_rating_fn = fertilizer_rating_fn,
         })
            :set_source(self._entity)
            :start()
      self._fertilize_task = fertilize_task
   end
end

return AceFarmerFieldComponent
