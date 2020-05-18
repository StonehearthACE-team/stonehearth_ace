--[[
   similar to the farmer field, the herbalist planter handles mass-growing of plants
      - focused on herbs/flowers (get rid of farmers growing them?)
      - instead of individually planting/watering/harvesting the plants, they're handled collectively (and with a single growth timer)
      - ai interacts with planters in several ways:
         - planting (hearthling collects X seeds and deposits them in the planter to start growing that type)
         - tending (hearthling does weeding/watering/pruning animations that improve quality)
         - harvesting (hearthling collects X products of quality based on herbalist level and amount of tending)
      - include small hidden storage component that slowly accumulates a few products while in harvestable state?
      - allow toggling harvesting (if disabled, can still accumulate products into storage)

   tracks both current_crop (what is currently selected by the player) and planted_crop (what has actually been planted by an herbalist)
      - need to continue rendering (and harvesting?) the planted crop while the herbalist is on their way to actually plant a new current crop
]]

local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local LootTable = require 'stonehearth.lib.loot_table.loot_table'

local HerbalistPlanterComponent = class()
local all_plant_data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter_crops')

local PLANT_ACTION = 'stonehearth_ace:plant_herbalist_planter'
local CLEAR_ACTION = 'stonehearth_ace:clear_herbalist_planter'

function HerbalistPlanterComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
end

function HerbalistPlanterComponent:create()
   self._is_create = true
   
   self._sv.allowed_crops = self._json.allowed_crops or all_plant_data.default_allowed_crops

   if self._json.default_crop and self._sv.allowed_crops[self._json.default_crop] then
      self:set_current_crop(self._json.default_crop)
   end
end

function HerbalistPlanterComponent:activate()
   local prev_num_products = self._sv.num_products
   self._sv.num_products = self._json.num_products or (self._json.plant_locations and #self._json.plant_locations) or 0
   if self._sv.num_products ~= prev_num_products then
      self.__saved_variables:mark_changed()
   end

   self._storage = self._entity:get_component('stonehearth:storage')

   local max_crop_level = 1
   for crop, data in pairs(all_plant_data.crops) do
      max_crop_level = math.max(max_crop_level, data.level or 1)
   end
   self._max_crop_level = max_crop_level

   self._tend_hard_cooldown = stonehearth.calendar:parse_duration(self._json.tend_hard_cooldown or 
         stonehearth.constants.herbalist_planters.TEND_HARD_COOLDOWN)
   self._quality_modification_interval = stonehearth.calendar:parse_duration(self._json.quality_modification_interval or 
         stonehearth.constants.herbalist_planters.DEFAULT_QUALITY_MODIFICATION_INTERVAL)

   self:_load_current_crop_stats()

   if self._is_create and self._json.start_planted then
      self:plant_crop()
   else
      self:_load_planted_crop_stats()
      self:_create_planter_tasks()
      self:_set_recently_tended_timer()
   end

   self:_create_listeners()
end

function HerbalistPlanterComponent:post_activate()
   if self._is_create then
      self:set_harvest_enabled(self._json.harvest_enabled ~= false)
   end
end

function HerbalistPlanterComponent:destroy()
   self:_stop_growth()
   self:_stop_bonus_growth()
   self:_stop_active_effect()
   self:_destroy_planter_tasks()
   self:_destroy_recently_tended_timer()
end

function HerbalistPlanterComponent:_create_listeners()
   self._added_to_world_listener = self._entity:add_component('mob'):trace_parent('planter added or removed')
      :on_changed(function(parent)
         if parent then
            self:_restart_timers()
         else
            local cur_time = stonehearth.calendar:get_elapsed_time()
            self:_stop_growth(cur_time)
            self:_stop_bonus_growth(cur_time)
         end
      end)
      :push_object_state()
end

-- if necessary, create the proper plant/clear task (harvesting and tending are handled in other ways)
function HerbalistPlanterComponent:_create_planter_tasks()
   self:_destroy_planter_tasks()

   if self:is_plantable() then
      local town = stonehearth.town:get_town(self._entity)
      
      local args = {
         planter = self._entity,
         seed_uri = self:get_seed_uri()
      }
      local action = args.seed_uri and PLANT_ACTION or CLEAR_ACTION
      
      local planter_task = town:create_task_for_group(
         'stonehearth_ace:task_groups:planters',
         action,
         args)
            :set_source(self._entity)
            :start()
      table.insert(self._added_planter_tasks, planter_task)
   end
end

function HerbalistPlanterComponent:_destroy_planter_tasks()
   if self._added_planter_tasks then
      for _, task in ipairs(self._added_planter_tasks) do
         task:destroy()
      end
   end
   self._added_planter_tasks = {}
end

function HerbalistPlanterComponent:_destroy_recently_tended_timer()
   if self._recently_tended_timer then
      self._recently_tended_timer:destroy()
      self._recently_tended_timer = nil
   end
   if self._quality_modification_timer then
      self._quality_modification_timer:destroy()
      self._quality_modification_timer = nil
   end
end

function HerbalistPlanterComponent:_stop_growth(cur_time)
   if self._sv._growth_timer then
      if cur_time then
         self._sv._growth_timer_duration_remaining = self._sv._growth_timer:get_expire_time() - cur_time
      end
      self._sv._growth_timer:destroy()
      self._sv._growth_timer = nil
   end
end

function HerbalistPlanterComponent:_stop_bonus_growth(cur_time)
   if self._sv._bonus_growth_timer then
      if cur_time then
         self._sv._bonus_growth_timer_duration_remaining = self._sv._bonus_growth_timer:get_expire_time() - cur_time
      end
      self._sv._bonus_growth_timer:destroy()
      self._sv._bonus_growth_timer = nil
   end
end

function HerbalistPlanterComponent:_stop_active_effect()
   if self._active_effect then
      self._active_effect:stop()
      self._active_effect = nil
   end
end

function HerbalistPlanterComponent:_reconsider()
   stonehearth.ai:reconsider_entity(self._entity, 'planter changed state for herbalist interaction')
end

function HerbalistPlanterComponent:_load_current_crop_stats()
   if not self._sv.current_crop then
      self._current_crop_stats = nil
   else
      self._current_crop_stats = all_plant_data.crops[self._sv.current_crop]
   end
end

function HerbalistPlanterComponent:_load_planted_crop_stats()
   if not self._sv.planted_crop then
      self._planted_crop_stats = nil
   else
      self._planted_crop_stats = all_plant_data.crops[self._sv.planted_crop]
      local growth_level = math.max(1, self._sv.crop_growth_level or 1)
      if self._planted_crop_stats and self._planted_crop_stats.growth_levels then
         local growth_level_data = self._planted_crop_stats.growth_levels[growth_level]
         
         if self._storage then
            self._bonus_product_uri = growth_level_data and (growth_level_data.bonus_product_uri or
                  self._planted_crop_stats.bonus_product_uri or self._planted_crop_stats.product_uri)
            self._bonus_product_loot_table = growth_level_data and (growth_level_data.bonus_product_loot_table or self._planted_crop_stats.bonus_product_loot_table)
         end

         self._quality_modification_rate = growth_level_data and growth_level_data.quality_modification_rate or self._planted_crop_stats.quality_modification_rate or
               stonehearth.constants.herbalist_planters.DEFAULT_QUALITY_MODIFICATION_RATE
      else
         self._bonus_product_uri = nil
         self._bonus_product_loot_table = nil
      end
   end
   self:_update_unit_crop_level()
end

function HerbalistPlanterComponent:set_harvest_enabled(enabled)
   if enabled ~= self._sv.harvest_enabled then
      self._sv.harvest_enabled = enabled
      self.__saved_variables:mark_changed()
      self:_reconsider()
   end
end

function HerbalistPlanterComponent:is_harvest_enabled()
   return self._sv.harvest_enabled
end

function HerbalistPlanterComponent:is_harvestable()
   return self._sv.harvestable and self:is_harvest_enabled()
end

function HerbalistPlanterComponent:is_plantable()
   return self._sv.planted_crop ~= self._sv.current_crop
end

function HerbalistPlanterComponent:is_tendable(level)
   if self._sv.planted_crop and self._planted_crop_stats then
      -- if a level is specified and the current crop is a higher level, no luck
      if level and level < self:get_planted_crop_level() then
         return false
      end
      
      -- if the recently tended timer is going, we're still in hard cooldown for tending
      return not self._recently_tended_timer
   else
      return false
   end
end

function HerbalistPlanterComponent:get_harvest_status_text()
   return self._planted_crop_stats and self._planted_crop_stats.harvest_status_text
end

function HerbalistPlanterComponent:get_plant_status_text()
   return self._planted_crop_stats and self._planted_crop_stats.plant_status_text
end

function HerbalistPlanterComponent:get_seed_uri()
   if self._current_crop_stats then
      return self._current_crop_stats.seed_uri
   end
end

function HerbalistPlanterComponent:get_product_uri()
   if self._planted_crop_stats then
      return self._planted_crop_stats.product_uri
   end
end

-- unit crop level is [0, 1] based on the planted crop level divided by the max level of all crops
function HerbalistPlanterComponent:get_unit_crop_level()
   return self._unit_crop_level
end

function HerbalistPlanterComponent:_update_unit_crop_level()
   self._unit_crop_level = self:get_planted_crop_level() / self._max_crop_level
end

function HerbalistPlanterComponent:get_planted_crop_level()
   return self._planted_crop_stats and self._planted_crop_stats.level or 1
end

function HerbalistPlanterComponent:get_harvester_effect()
   return self._planted_crop_stats and self._planted_crop_stats.harvester_effect or 'fiddle'
end

function HerbalistPlanterComponent:get_planter_effect()
   return self._planted_crop_stats and self._planted_crop_stats.planter_effect or 'fiddle'
end

function HerbalistPlanterComponent:run_planter_harvest_effect()
   self:_set_active_effect(self._json.harvest_effect)
end

function HerbalistPlanterComponent:run_planter_plant_effect()
   self:_set_active_effect(self._json.plant_effect)
end

function HerbalistPlanterComponent:stop_active_effect()
   self:_stop_active_effect()
end

function HerbalistPlanterComponent:_reset_growth()
   self._sv.crop_growth_level = 0
   self._sv.harvestable = false
   self.__saved_variables:mark_changed()
   self:_grow()
   self:_reconsider()
end

function HerbalistPlanterComponent:_reset_tend_quality(multiplier)
   local expendable = self._entity:get_component('stonehearth:expendable_resources')
   if expendable then
      local value = expendable:get_min_value('tend_quality') or 0
      if self._sv.seed_quality then
         value = math.max(self._sv.seed_quality, value)
      end
      
      if multiplier then
         value = value + ((expendable:get_value('tend_quality') or 0) - value) * multiplier
      end
      expendable:set_value('tend_quality', value)
   end
end

function HerbalistPlanterComponent:_grow()
   self:_stop_growth()
   self:_stop_bonus_growth()

   if self._planted_crop_stats and self._sv.crop_growth_level then
      self._sv.crop_growth_level = math.min(self._sv.crop_growth_level + 1, #self._planted_crop_stats.growth_levels)
      self._sv._bonus_growth_period = nil
      local growth_level_data = self._planted_crop_stats.growth_levels[self._sv.crop_growth_level]

      -- if relevant, start a timer for the next growth level
      if self._sv.crop_growth_level < #self._planted_crop_stats.growth_levels then
         local growth_time = growth_level_data and growth_level_data.growth_time or self._planted_crop_stats.growth_time
         local growth_period = stonehearth.calendar:parse_duration(growth_time)
         growth_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), growth_period)
         self._sv._growth_timer_duration_remaining = growth_period
      else
         -- otherwise, set harvestable
         self._sv.harvestable = true
         self:_reconsider()
      end

      -- if relevant, start timer for bonus product creation to storage
      if self._storage then
         local bonus_product_growth_time = growth_level_data.bonus_product_growth_time or (self._sv.harvestable and self._planted_crop_stats.bonus_product_growth_time)
         if bonus_product_growth_time then
            local bonus_growth_period = stonehearth.calendar:parse_duration(bonus_product_growth_time)
            bonus_growth_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), bonus_growth_period)
            self._sv._bonus_growth_period = bonus_growth_period
            self._sv._bonus_growth_timer_duration_remaining = bonus_growth_period
            self._bonus_product_uri = growth_level_data.bonus_product_uri or self._planted_crop_stats.bonus_product_uri or self._planted_crop_stats.product_uri
            self._bonus_product_loot_table = growth_level_data.bonus_product_loot_table or self._planted_crop_stats.bonus_product_loot_table
         end
      end

      self:_restart_timers()
      self.__saved_variables:mark_changed()
   end
end

function HerbalistPlanterComponent:_restart_timers()
   -- only actually start the timers if we're in the world
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   if self._sv._growth_timer_duration_remaining and not self._sv._growth_timer then
      self._sv._growth_timer = stonehearth.calendar:set_persistent_timer("herbalist_planter growth",
            self._sv._growth_timer_duration_remaining, radiant.bind(self, '_grow'))
      self._sv._growth_timer_duration_remaining = nil
   end

   if not self._sv._bonus_growth_timer then
      local time = self._sv._bonus_growth_timer_duration_remaining or self._sv._bonus_growth_period
      if time then
         self._sv._bonus_growth_timer = stonehearth.calendar:set_persistent_timer("herbalist_planter growth", time, radiant.bind(self, '_bonus_grow'))
         self._sv._bonus_growth_timer_duration_remaining = nil
      end
   end
end

-- create bonus product and stick in storage
-- if there's no space, destroy an existing different item if possible
function HerbalistPlanterComponent:_bonus_grow()
   self:_stop_bonus_growth()

   if not self._storage then
      return
   end

   if not self._storage:is_full() and (self._bonus_product_uri or self._bonus_product_loot_table) then
      --local player_id = self._entity:get_player_id()
      local num_products = math.min(self._json.num_bonus_products or 1, self._storage:get_capacity() - self._storage:get_num_items())
      self:_create_products(nil, self._bonus_product_uri, num_products, self._bonus_product_loot_table)
   end

   self:_restart_timers()
end

function HerbalistPlanterComponent:_create_product(items, quality, input, spill_failed, owner, location)
   return radiant.entities.output_items(items, location, 0, 1, { owner = owner }, self._entity, input, spill_failed, quality)
end

function HerbalistPlanterComponent:_create_products(harvester, product_uri, quantity, loot_table_data)
   local quality = self:_get_quality()
   local input = harvester or self._entity
   local spill_failed = harvester ~= nil
   local owner = self._entity:get_player_id()
   local location = radiant.entities.get_world_grid_location(input)
   
   local items
   if product_uri and quantity > 0 then
      items = self:_create_product({[product_uri] = quantity}, quality, input, spill_failed, owner, location)
   end

   local loot_table_items
   local loot_table = loot_table_data and LootTable(loot_table_data)
   if loot_table then
      for i = 1, quantity do
         local these_loot_table_items = self:_create_product(loot_table:roll_loot(), quality, input, spill_failed, owner, location)
         if these_loot_table_items then
            if loot_table_items then
               loot_table_items = radiant.entities.combine_output_tables(these_loot_table_items, loot_table_items)
            else
               loot_table_items = these_loot_table_items
            end
         end
      end
   end

   return (items or loot_table_items) and radiant.entities.combine_output_tables(items, loot_table_items)
end

-- called by ai to harvest the planter
function HerbalistPlanterComponent:create_products(harvester)
   if self:is_harvestable() then
      local items
      if self._planted_crop_stats then
         items = self:_create_products(harvester, self._planted_crop_stats.product_uri, self._sv.num_products, self._planted_crop_stats.additional_products)
      end
      self:_reset_growth()
      self:_reset_tend_quality(0.5)

      return items
   end
end

function HerbalistPlanterComponent:set_harvest_enabled_command(session, response, enabled)
   self:set_harvest_enabled(enabled)
   return true
end

function HerbalistPlanterComponent:set_current_crop_command(session, response, crop)
   if crop ~= self._sv.current_crop then
      self:set_current_crop(crop)
      return true
   else
      return false
   end
end

function HerbalistPlanterComponent:set_current_crop(crop)
   self._sv.current_crop = crop
   self.__saved_variables:mark_changed()
   self:_load_current_crop_stats()
   self:_create_planter_tasks()
end

-- ai will call this to set the planted crop to the current crop selection and start it growing
-- this also gets called to clear the planted crop (when current_crop is nil)
function HerbalistPlanterComponent:plant_crop(planter, seed)
   if self._sv.current_crop then
      self._sv.planted_crop = self._sv.current_crop
      self._sv.seed_quality = seed and radiant.entities.get_item_quality(seed) or 1
   else
      self._sv.planted_crop = nil
      self._sv.seed_quality = nil
   end
   self:_load_planted_crop_stats()

   -- dump out all bonus products in storage; should they just get destroyed instead? this is nicer
   if self._storage then
      self._storage:drop_all(planter and radiant.entities.get_world_grid_location(planter))
   end

   self:_reset_growth()
   self:_reset_tend_quality()
   self:tend_to_crop(planter, 0)
   self:_destroy_planter_tasks()
end

-- used by ai to determine how in need of tending this planter is
function HerbalistPlanterComponent:get_last_tended()
   return self._sv._last_tended or 0
end

function HerbalistPlanterComponent:tend_to_crop(tender, amount)
   if self._sv.planted_crop then
      local tend_amount = amount
      if not tend_amount then
         local job_component = tender and tender:get_component('stonehearth:job')
         local job_controller = job_component and job_component:get_curr_job_controller()
         if job_controller and job_controller.get_planter_tend_amount then
            tend_amount = job_controller:get_planter_tend_amount()
         else
            tend_amount = 0
         end
      end
      self:_modify_tend_quality(tend_amount * (self._planted_crop_stats.tending_multiplier or 1))
      self._sv._last_tended = stonehearth.calendar:get_elapsed_time()
      self:_set_recently_tended_timer()
      self:_set_quality_table(tender)
      self:_reconsider()
   end
end

function HerbalistPlanterComponent:_set_recently_tended_timer()
   self:_destroy_recently_tended_timer()

   local duration = self._tend_hard_cooldown - (stonehearth.calendar:get_elapsed_time() - self:get_last_tended())
   if duration > 0 then
      self._recently_tended_timer = stonehearth.calendar:set_timer('herbalist_planter recently tended', 
            self._tend_hard_cooldown,
            function()
               -- all we care about is whether this timer currently exists
               self:_destroy_recently_tended_timer()
               self:_reconsider()
            end)
   end

   -- also set up an interval for reducing quality periodically (reset whenever it's tended)
   local expendable = self._entity:get_component('stonehearth:expendable_resources')
   if expendable and self._planted_crop_stats then
      self._quality_modification_timer = stonehearth.calendar:set_interval('herbalist_planter periodic quality modification',
         self._quality_modification_interval,
         function()
            expendable:modify_value('tend_quality', self._quality_modification_rate)
         end)
   end
end

function HerbalistPlanterComponent:_get_tend_quality()
   local expendable = self._entity:get_component('stonehearth:expendable_resources')
   return expendable and expendable:get_value('tend_quality') or 1
end

function HerbalistPlanterComponent:_modify_tend_quality(amount)
   local expendable = self._entity:get_component('stonehearth:expendable_resources')
   if expendable then
      expendable:modify_value('tend_quality', amount)
   end
end

function HerbalistPlanterComponent:_get_quality()
   local max_quality = item_quality_lib.get_max_crafting_quality(self._entity:get_player_id())
   local ingredient_quality = math.max(1, math.min(max_quality, self:_get_tend_quality()))
   return self._sv._quality_table and item_quality_lib.modify_quality_table(self._sv._quality_table, ingredient_quality)
end

function HerbalistPlanterComponent:_set_quality_table(tender)
   self._sv._quality_table = tender and item_quality_lib.get_quality_table(tender, self._planted_crop_stats.level or 1)
   local quality_buff = self._json.quality_buffs and self._json.quality_buffs[math.min(math.floor(self:_get_tend_quality()), #self._json.quality_buffs)]
   if quality_buff then
      self._entity:add_component('stonehearth:buffs'):add_buff(quality_buff)
   end
end

-- use this for ai interactions (e.g., dirt cloud effect for planting)?
function HerbalistPlanterComponent:_set_active_effect(effect)
   self:_stop_active_effect()
   if effect then
      self._active_effect = radiant.effects.run_effect(self._entity, effect)
            :set_cleanup_on_finish(false)
   end
end

return HerbalistPlanterComponent
