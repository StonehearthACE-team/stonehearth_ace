local ConsumptionComponent = require 'stonehearth.components.consumption.consumption_component'
local log = radiant.log.create_logger('consumption')

local AceConsumptionComponent = class()

local DRINK_DESIRE_AMOUNT = 3

AceConsumptionComponent.THIRST_SATED = 1
AceConsumptionComponent.THIRST_NEUTRAL = 2
AceConsumptionComponent.THIRSTY = 3
AceConsumptionComponent.VERY_THIRSTY = 4

AceConsumptionComponent._ace_old_activate = ConsumptionComponent.activate
function AceConsumptionComponent:activate()
   self._sv._consumes_drinks = nil

   self._sv._food_intolerances = ''
   self._sv._drink_preferences = ''
   self._sv._drink_intolerances = ''
   self._sv._last_drink_thoughts = {}
   self._sv._drink_window_expire_time = nil
   self._sv._last_drinking_time = nil

   self:_ace_old_activate()

   local ds = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:drink_satiety')
   if ds then
      self._sv._consumes_drinks = true
      self._drink_satiety_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:drink_satiety', self, self._on_drink_satiety_changed)

      local ds = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:drink_satiety')
      self._thirsty_threshold = ds and ds.thirsty_threshold or stonehearth.constants.drink_satiety.THIRSTY
      self._very_thirsty_threshold = ds and ds.very_thirsty_threshold or stonehearth.constants.drink_satiety.VERY_THIRSTY
      self._hourly_drink_satiety_loss = ds and ds.hourly_drink_satiety_loss or stonehearth.constants.drink_satiety.HOURLY_DRINK_SATIETY_LOSS
      self._morning_time = ds and ds.morning_time or -1
      self._afternoon_time = ds and ds.afternoon_time or -1
      self._night_time = ds and ds.night_time or -1
      self._drink_qualities = ds and ds.drink_qualities or {}

      self._max_drink_satiety_listener = radiant.events.listen(self._entity, 'stonehearth:attribute_changed:max_drink_satiety', self, self._on_max_drink_satiety_changed)
      self:_on_max_drink_satiety_changed()
   end
end

AceConsumptionComponent._ace_old_post_activate = ConsumptionComponent.post_activate
function AceConsumptionComponent:post_activate()
   self:_ace_old_post_activate()

   local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity))
   if inventory and inventory:get_desires() and self._sv._consumes_drinks then
      self._drink_desire_request = inventory:get_desires():request_material('drink_container', math.floor(DRINK_DESIRE_AMOUNT * self._hourly_drink_satiety_loss))
   end
end

AceConsumptionComponent._ace_old_destroy = ConsumptionComponent.__user_destroy
function AceConsumptionComponent:destroy()
   self:_ace_old_destroy()

   if self._drink_satiety_listener then
      self._drink_satiety_listener:destroy()
      self._drink_satiety_listener = nil
   end

   if self._max_drink_satiety_listener then
      self._max_drink_satiety_listener:destroy()
      self._max_drink_satiety_listener = nil
   end

   if self._drink_desire_request then
      self._drink_desire_request:destroy()
      self._drink_desire_request = nil
   end
end

AceConsumptionComponent._ace_old_set_food_preferences = ConsumptionComponent.set_food_preferences
function AceConsumptionComponent:set_food_preferences(preferences, effect)
   self._sv._preference_effect = effect
   self:_ace_old_set_food_preferences(preferences)
end

function AceConsumptionComponent:set_food_intolerances(intolerances, effect)
   self._sv._food_intolerances = intolerances
   self._sv._intolerance_effect = effect
end

AceConsumptionComponent._ace_old__should_add_food_thought = ConsumptionComponent._should_add_food_thought
function AceConsumptionComponent:_should_add_food_thought(food_quality, now)
   if food_quality <= stonehearth.constants.food_qualities.UNPALATABLE then
      return true
   else
      return self:_ace_old__should_add_food_thought(food_quality, now)
   end
end

function AceConsumptionComponent:_get_quality(food)
   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data then
      radiant.assert(false, 'Trying to eat a piece of food that has no entity data.')
      return -1
   end

   -- first check if intolerable
   if self:_has_food_intolerances() then
      if radiant.entities.is_material(food, self._sv._food_intolerances) then
         if self._sv._intolerance_effect then
            radiant.entities.add_buff(self._entity, self._sv._intolerance_effect)
            return stonehearth.constants.food_qualities.INTOLERABLE
         else
            return stonehearth.constants.food_qualities.UNPALATABLE
         end
      end
   end

   -- apply buffs if not intolerable; intolerable food will ignore any applied buffs.
   if food_data.applied_buffs then
      for _, applied_buff in ipairs(food_data.applied_buffs) do
         radiant.entities.add_buff(self._entity, applied_buff)
      end
   end

   -- then check if lovely
   if self:_has_food_preferences() and self._sv._preference_effect then
      if radiant.entities.is_material(food, self._sv._food_preferences) then
         radiant.entities.add_buff(self._entity, self._sv._preference_effect)
         return stonehearth.constants.food_qualities.LOVELY
      end
   end


   if not food_data.quality then
      log:error('Food %s has no quality entry, defaulting quality to raw & bland.', food)
   end

   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
end

function AceConsumptionComponent:_has_food_intolerances()
   return self._sv._food_intolerances ~= ''
end

function AceConsumptionComponent:get_food_intolerances()
   return self._sv._food_intolerances
end

-- override this function to avoid recalculating things when just adding drink_satiety modification
function AceConsumptionComponent:consume_calories(food_entity)
   local entity = self._entity
   local food_quality = self:_get_quality(food_entity)
   local food_data = self:_get_food_data(food_entity)

   local eat_event_data = {
      consumer = entity,
      time = stonehearth.calendar:get_time_and_date(),
      food_uri = food_entity:get_uri(),
      food_data = food_data,
      food_name = radiant.entities.get_display_name(food_entity),
      food_quality = food_quality
   }
   self:_add_food_thoughts(eat_event_data, food_entity)
   radiant.events.trigger_async(entity, 'stonehearth:eat_food', eat_event_data)

   local satisfaction = food_data.satisfaction
   if self:_has_food_preferences() and food_quality > stonehearth.constants.food_qualities.UNPALATABLE then
      satisfaction = satisfaction * stonehearth.constants.food.PREFERRED_FOOD_BONUS
   end
   self._expendable_resources_component:modify_value('calories', satisfaction)

   local drink_satisfaction = food_data.drink_satisfaction
   if drink_satisfaction then
      -- don't apply a multiplier for a negative effect
      if drink_satisfaction > 0 and self:_has_drink_preferences() and food_quality > stonehearth.constants.food_qualities.UNPALATABLE then
         drink_satisfaction = drink_satisfaction * stonehearth.constants.drink_satiety.PREFERRED_DRINK_BONUS
      end
      self._expendable_resources_component:modify_value('drink_satiety', drink_satisfaction)
   end

   self._sv._last_eating_time = stonehearth.calendar:get_elapsed_time()
end

AceConsumptionComponent._ace_old__on_hourly = ConsumptionComponent._on_hourly
function AceConsumptionComponent:_on_hourly()
   if self._sv._consumes_drinks then
      self:_lose_drink_satiety()
   end

   self:_ace_old__on_hourly()
end

-- Drinking related functions are below
function AceConsumptionComponent:get_drink_satiety_state()
   local drink_satiety = self._expendable_resources_component:get_value('drink_satiety')
   if drink_satiety > self._thirst_sated_threshold then
      return AceConsumptionComponent.THIRST_SATED
   elseif drink_satiety <= self._very_thirsty_threshold then
      return AceConsumptionComponent.VERY_THIRSTY
   elseif drink_satiety <= self._thirsty_threshold then
      return AceConsumptionComponent.THIRSTY
   end
   return AceConsumptionComponent.THIRST_NEUTRAL
end

function AceConsumptionComponent:get_thirst_score()
   local drink_satiety = self._expendable_resources_component:get_value('drink_satiety')
   if drink_satiety <= self._very_thirsty_threshold then
      return 1.0
   elseif drink_satiety <= self._thirsty_threshold then
      return 0.5 + 0.5 * (1 - (drink_satiety - self._very_thirsty_threshold) / (self._thirsty_threshold - self._very_thirsty_threshold))
   else
      return 0.5 * (1 - (drink_satiety - self._thirsty_threshold) / (self._thirst_sated_threshold - self._thirsty_threshold))
   end
end

function AceConsumptionComponent:get_min_thirst_to_drink_now()
   local now = stonehearth.calendar:get_time_and_date()

   local minutes_to_drink_time = nil
   if now.hour == self._morning_time or now.hour == self._afternoon_time or now.hour == self._night_time then
      minutes_to_drink_time = now.minute
   elseif now.hour == self._morning_time - 1 or now.hour == self._night_time - 1 then
      minutes_to_drink_time = 60 - now.minute
   elseif now.hour == self._afternoon_time - 1 then
      local drink_satiety = self._expendable_resources_component:get_value('drink_satiety')
      if drink_satiety <= self._thirsty_threshold then
         minutes_to_drink_time = 60 - now.minute
      end
   end

   local time_since_last_drink = stonehearth.calendar:get_elapsed_time() - (self._sv._last_drinking_time or 0)
   local had_drink_recently = time_since_last_drink <= stonehearth.constants.drink_satiety.HAD_DRINK_RECENTLY_WINDOW

   local threshold = 0.25
   if minutes_to_drink_time ~= nil then
      threshold = threshold * (minutes_to_drink_time / 60)
   end
   if had_drink_recently then
      threshold = threshold - 0.1
   end
   return threshold
end

function AceConsumptionComponent:set_drink_preferences(preferences, effect)
   self._sv._drink_preference_effect = effect
   self._sv._drink_preferences = preferences
end

function AceConsumptionComponent:set_drink_intolerances(intolerances, effect)
   self._sv._drink_intolerances = intolerances
   self._sv._drink_intolerance_effect = effect
end

function AceConsumptionComponent:consume_drink(drink_entity)
   local entity = self._entity
   local drink_quality = self:_get_drink_quality(drink_entity)
   local drink_data = self:_get_drink_data(drink_entity)

   local drink_event_data = {
      consumer = entity,
      time = stonehearth.calendar:get_time_and_date(),
      drink_uri = drink_entity:get_uri(),
      drink_data = drink_data,
      drink_name = radiant.entities.get_display_name(drink_entity),
      drink_quality = drink_quality
   }
   self:_add_drink_thoughts(drink_event_data, drink_entity)
   radiant.events.trigger_async(entity, 'stonehearth_ace:consume_drink', drink_event_data)

   local satisfaction = drink_data.satisfaction
   if self:_has_drink_preferences() and drink_quality > stonehearth.constants.drink_qualities.UNPALATABLE then
      satisfaction = satisfaction * stonehearth.constants.drink_satiety.PREFERRED_DRINK_BONUS
   end
   self._expendable_resources_component:modify_value('drink_satiety', satisfaction)

   local food_satisfaction = drink_data.food_satisfaction
   if food_satisfaction then
      -- don't apply a multiplier for a negative effect
      if food_satisfaction > 0 and self:_has_food_preferences() and drink_quality > stonehearth.constants.drink_qualities.UNPALATABLE then
         food_satisfaction = food_satisfaction * stonehearth.constants.food.PREFERRED_FOOD_BONUS
      end
      self._expendable_resources_component:modify_value('calories', food_satisfaction)
   end

   self._sv._last_drinking_time = stonehearth.calendar:get_elapsed_time()
end

function AceConsumptionComponent:add_drink_thought(thought, drink_quality, drink_uri, drink_name)
   if self:_should_add_drink_thought(drink_quality) then
      self:_add_drink_thought(thought, drink_quality, drink_uri, drink_name)
   end
end

function AceConsumptionComponent:_get_thought_for_drink_quality(drink_quality)
   local thoughts = stonehearth.constants.drink_quality_thoughts[drink_quality]
   assert(thoughts, 'There is no thought found for drink quality %s', drink_quality)
   return thoughts
end

function AceConsumptionComponent:_add_drink_thought(thought, drink_quality, drink_uri, drink_name)
   local last_drink_thoughts = self._sv._last_drink_thoughts[drink_uri]
   if not last_drink_thoughts then
      self._sv._last_drink_thoughts[drink_uri] = {
         drink_quality = drink_quality,
         drink_thoughts = {}
      }
      last_drink_thoughts = self._sv._last_drink_thoughts[drink_uri]
   end
   local drink_thoughts = last_drink_thoughts.drink_thoughts
   table.insert(drink_thoughts, thought)

   radiant.entities.add_thought(self._entity, thought, { tooltip_args = { drinkname = drink_name } })
end

function AceConsumptionComponent:_add_drink_thoughts(e, drink_entity)
   local now = stonehearth.calendar:get_elapsed_time()

   local add_new_thoughts = self:_should_add_drink_thought(e.drink_quality)

   self._sv._drink_window_expire_time = self:_get_end_time(now, stonehearth.constants.drink_satiety.DRINK_TIME_WINDOW)

   if add_new_thoughts then
      self:_update_last_drink_thoughts(e.drink_quality)
      local drink_thoughts = self:_get_thought_for_drink_quality(e.drink_quality)
      local drink_name = e.drink_name or 'i18n(stonehearth_ace:entities.drink.unknown_drink.display_name)'
      for _, thought in pairs(drink_thoughts) do
         self:_add_drink_thought(thought, e.drink_quality, e.drink_uri, e.drink_name)
      end
   end

   self:_add_drink_item_quality_thought(e, drink_entity)
end

function AceConsumptionComponent:_should_add_drink_thought(drink_quality, now)
   if drink_quality <= stonehearth.constants.drink_qualities.UNPALATABLE then
      return true
   else
      local now = stonehearth.calendar:get_elapsed_time()

      if drink_quality == stonehearth.constants.drink_qualities.UNPALATABLE then
         return true
      elseif not self._sv._drink_window_expire_time or now >= self._sv._drink_window_expire_time then
         return true
      elseif now < self._sv._drink_window_expire_time then
         for uri, data in pairs(self._sv._last_drink_thoughts) do
            if drink_quality >= data.drink_quality then
               return true
            end
         end
      end
   end

   return false
end

function AceConsumptionComponent:_update_last_drink_thoughts(drink_quality)
   local now = stonehearth.calendar:get_elapsed_time()

   if drink_quality == stonehearth.constants.drink_qualities.UNPALATABLE then
      for _, data in pairs(self._sv._last_drink_thoughts) do
         for _, thought in pairs(data.drink_thoughts) do
            radiant.entities.remove_thought(self._entity, thought)
         end
      end
      self._sv._last_drink_thoughts = {}
   elseif not self._sv._drink_window_expire_time or now >= self._sv._drink_window_expire_time then
      self._sv._last_drink_thoughts = {}
   elseif now < self._sv._drink_window_expire_time then
      for uri, data in pairs(self._sv._last_drink_thoughts) do
         if drink_quality >= data.drink_quality then
            local drink_thoughts = data.drink_thoughts
            for _, thought in pairs(drink_thoughts) do
               radiant.entities.remove_thought(self._entity, thought)
            end
            self._sv._last_drink_thoughts[uri] = nil
         end
      end
   end
end

function ConsumptionComponent:_add_drink_item_quality_thought(event, drink_entity)
   local quality_component = drink_entity:get_component('stonehearth:item_quality')
   local quality = (quality_component and quality_component:get_quality()) or 0
   if quality >= stonehearth.constants.item_quality.FINE then
      local thought = stonehearth.constants.drink_item_quality_thoughts[quality]
      if thought then
           radiant.entities.add_thought(self._entity, thought, { tooltip_args = { drinkname = event.drink_name } })
        end
   end
end

function AceConsumptionComponent:_on_drink_satiety_changed()
   local drink_satiety = self._expendable_resources_component:get_value('drink_satiety')
   if drink_satiety <= self._very_thirsty_threshold then
      radiant.events.trigger_async(self._entity, 'stonehearth:very_thirsty_event')
   end
end

function AceConsumptionComponent:_lose_drink_satiety()
   local ic = self._entity:get_component('stonehearth:incapacitation')
   if ic and ic:is_incapacitated() then
      return
   end

   local drink_satiety_loss_multiplier = self._attributes_component:get_attribute('drink_satiety_loss_multiplier')
   local drink_satiety_lost = self._hourly_drink_satiety_loss * drink_satiety_loss_multiplier

   self._expendable_resources_component:modify_value('drink_satiety', -drink_satiety_lost)
end

function AceConsumptionComponent:_on_max_drink_satiety_changed()
   self._thirst_sated_threshold = self._attributes_component:get_attribute('max_drink_satiety')
end

function AceConsumptionComponent:_get_drink_quality(drink)
   local drink_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink', false)

   if not drink_data then
      radiant.assert(false, 'Trying to consume a drink that has no entity data.')
      return -1
   end

   -- first check if intolerable
   if self:_has_drink_intolerances() then
      if radiant.entities.is_material(drink, self._sv._drink_intolerances) then
         if self._sv._drink_intolerance_effect then
            radiant.entities.add_buff(self._entity, self._sv._drink_intolerance_effect)
            return stonehearth.constants.drink_qualities.INTOLERABLE
         else
            return stonehearth.constants.drink_qualities.UNPALATABLE
         end
      end
   end

   -- apply buffs if not intolerable; intolerable drinks will ignore any applied buffs.
   if drink_data.applied_buffs then
      for _, applied_buff in ipairs(drink_data.applied_buffs) do
         radiant.entities.add_buff(self._entity, applied_buff)
      end
   end

   -- then check if lovely
   if self:_has_drink_preferences() and self._sv._drink_preference_effect then
      if radiant.entities.is_material(drink, self._sv._drink_preferences) then
         radiant.entities.add_buff(self._entity, self._sv._drink_preference_effect)
         return stonehearth.constants.drink_qualities.LOVELY
      end
   end


   if not drink_data.quality then
      log:error('Drink %s has no quality entry, defaulting quality to raw & bland.', drink)
   end

   return drink_data.quality or stonehearth.constants.drink_qualities.RAW_BLAND

end

function AceConsumptionComponent:_get_drink_data(drink)
   local drink_entity_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink')
   local drink_data

   if drink_entity_data then
      local posture = radiant.entities.get_posture(self._entity)
      drink_data = drink_entity_data[posture]

      if not drink_data then
         drink_data = drink_entity_data.default
      end
   end

   return drink_data
end

function AceConsumptionComponent:_has_drink_intolerances()
   return self._sv._drink_intolerances ~= ''
end

function AceConsumptionComponent:get_drink_intolerances()
   return self._sv._drink_intolerances
end

function AceConsumptionComponent:_has_drink_preferences()
   return self._sv._drink_preferences ~= ''
end

function AceConsumptionComponent:get_drink_preferences()
   return self._sv._drink_preferences
end

function AceConsumptionComponent:distinguishes_drink_quality()
   return next(self._drink_qualities) ~= nil
end

return AceConsumptionComponent