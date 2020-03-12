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

local HerbalistPlanterComponent = class()
local all_plant_data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter_crops')

local PLANT_ACTION = 'stonehearth_ace:plant_herbalist_planter'
local CLEAR_ACTION = 'stonehearth_ace:clear_herbalist_planter'

function HerbalistPlanterComponent:create()
   self._json = radiant.entities.get_json(self) or {}
   
   self._sv._amount_tended = 0    -- use effects to make the planter sparkle a bit with more tending?
   self._sv.allowed_crops = self._json.allowed_crops or all_plant_data.default_allowed_crops

   -- DEBUG: until UI implemented
   self:set_current_crop('brightbell')
end

function HerbalistPlanterComponent:restore()
   self._json = radiant.entities.get_json(self)
end

function HerbalistPlanterComponent:activate()
   self._num_crops = self._json.plant_locations and #self._json.plant_locations or 0
   self._storage = self._entity:get_component('stonehearth:storage')

   local max_crop_level = 1
   for crop, data in pairs(all_plant_data.crops) do
      max_crop_level = math.max(max_crop_level, data.level or 1)
   end
   self._max_crop_level = max_crop_level

   self._max_tending_quality = stonehearth.constants.herbalist_planters.MAX_TENDING_QUALITY
   self._tend_hard_cooldown = stonehearth.calendar:parse_duration(stonehearth.constants.herbalist_planters.TEND_HARD_COOLDOWN)

   self:_load_current_crop_stats()
   self:_load_planted_crop_stats()
   self:_create_listeners()
   self:_create_planter_tasks()
   self:_set_recently_tended_timer()
end

function HerbalistPlanterComponent:destroy()
   self:_stop_growth()
   self:_stop_bonus_growth()
   self:_stop_active_effect()
   self:_destroy_listeners()
   self:_destroy_planter_tasks()
   self:_destroy_recently_tended_timer()
end

function HerbalistPlanterComponent:_create_listeners()
   self._enabled_listener = radiant.events.listen(self._entity, 'stonehearth_ace:enabled_changed',
      function(enabled)
         self:_reconsider()
      end)
end

function HerbalistPlanterComponent:_destroy_listeners()
   if self._enabled_listener then
      self._enabled_listener:destroy()
      self._enabled_listener = nil
   end
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
end

function HerbalistPlanterComponent:_stop_growth()
   if self._sv._growth_timer then
      self._sv._growth_timer:destroy()
      self._sv._growth_timer = nil
   end
end

function HerbalistPlanterComponent:_stop_bonus_growth()
   if self._sv._bonus_growth_timer then
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
   end
   self:_update_unit_crop_level()
end

function HerbalistPlanterComponent:_is_enabled()
   local toggle_comp = self._entity:get_component('stonehearth_ace:toggle_enabled')
   return not toggle_comp or toggle_comp:get_enabled()
end

function HerbalistPlanterComponent:is_harvestable()
   return self._sv.harvestable and self:_is_enabled()
end

function HerbalistPlanterComponent:is_plantable()
   return self._sv.planted_crop ~= self._sv.current_crop
end

function HerbalistPlanterComponent:is_tendable()
   if self._sv.planted_crop and self._planted_crop_stats then
      -- if the recently tended timer is going, we're still in hard cooldown for tending
      return self._sv.crop_growth_level < #self._planted_crop_stats.growth_levels and not self._recently_tended_timer
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
   self._unit_crop_level = (self._planted_crop_stats and self._planted_crop_stats.level or 1) / self._max_crop_level
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
   self._sv._amount_tended = 0
   self._sv.crop_growth_level = 0
   self._sv.harvestable = false
   self.__saved_variables:mark_changed()
   self:_grow()
   self:_reconsider()
end

function HerbalistPlanterComponent:_grow()
   self:_stop_growth()
   self:_stop_bonus_growth()

   if self._planted_crop_stats and self._sv.crop_growth_level then
      self._sv.crop_growth_level = math.min(self._sv.crop_growth_level + 1, #self._planted_crop_stats.growth_levels)
      local growth_level_data = self._planted_crop_stats.growth_levels[self._sv.crop_growth_level]

      -- if relevant, start a timer for the next growth level
      if self._sv.crop_growth_level < #self._planted_crop_stats.growth_levels then
         local growth_time = growth_level_data and growth_level_data.growth_time or self._planted_crop_stats.growth_time
         local growth_period = stonehearth.calendar:parse_duration(growth_time)
         growth_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), growth_period)
         self._sv._growth_timer = stonehearth.calendar:set_persistent_timer("herbalist_planter growth", growth_period, radiant.bind(self, '_grow'))
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
            self._sv._bonus_growth_timer = stonehearth.calendar:set_persistent_interval("herbalist_planter growth", bonus_growth_period, radiant.bind(self, '_bonus_grow'))
            self._bonus_product_uri = growth_level_data.bonus_product_uri or self._planted_crop_stats.bonus_product_uri or self._planted_crop_stats.product_uri
         end
      end

      self.__saved_variables:mark_changed()
   end
end

-- create bonus product and stick in storage
-- if there's no space, destroy an existing different item if possible
function HerbalistPlanterComponent:_bonus_grow()
   if not self._storage then
      return
   end

   if self._storage:is_full() then
      for id, item in pairs(self._storage:get_items()) do
         if item and (not item:is_valid() or item:get_uri() ~= self._bonus_product_uri) then
            self._storage:remove_item(id)
            radiant.entities.destroy_entity(item)
            break
         end
      end
   end

   if not self._storage:is_full() then
      --local player_id = self._entity:get_player_id()
      self:_create_product(self._bonus_product_uri, 1, self._entity)
   end
end

function HerbalistPlanterComponent:_create_product(product_uri, quantity, input)
   local quality = self._sv._quality or 1
   return radiant.entities.output_items({[product_uri] = quantity or 1}, radiant.entities.get_world_grid_location(self._entity), 0, 1, 
                                        { owner = self._entity:get_player_id() }, self._entity, input, input ~= nil, quality)
end

-- called by ai to harvest the planter
function HerbalistPlanterComponent:create_products(harvester)
   if self:is_harvestable() then
      local items
      if self._planted_crop_stats and self._planted_crop_stats.product_uri and self._num_crops > 0 then
         items = self:_create_product(self._planted_crop_stats.product_uri, self._num_crops, harvester)
      end
      self:_reset_growth()

      return items
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
function HerbalistPlanterComponent:plant_crop(planter)
   if self._sv.current_crop then
      self._sv.planted_crop = self._sv.current_crop
   else
      self._sv.planted_crop = nil
   end
   self:_load_planted_crop_stats()

   self:_reset_growth()
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
         local job_component = tender:get_component('stonehearth:job')
         local job_controller = job_component and job_component:get_curr_job_controller()
         if job_controller and job_controller.get_planter_tend_amount then
            tend_amount = job_controller:get_planter_tend_amount()
         else
            tend_amount = 0
         end
      end
      self._sv._amount_tended = self._sv._amount_tended + tend_amount * (self._planted_crop_stats.tending_multiplier or 1)
      self._sv._last_tended = stonehearth.calendar:get_elapsed_time()
      self:_set_recently_tended_timer()
      self:_update_quality(tender)
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
end

function HerbalistPlanterComponent:_update_quality(tender)
   self._sv._quality = item_quality_lib.get_quality_table(tender, self._planted_crop_stats.level or 1, math.max(1, math.min(self._max_tending_quality, self._sv._amount_tended)))
   
   local quality_buff = self._json.quality_buffs and self._json.quality_buffs[math.min(math.floor(self._sv._amount_tended), #self._json.quality_buffs)]
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
