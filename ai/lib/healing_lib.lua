--[[

]]

local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local healing_lib = {}

local log = radiant.log.create_logger('healing_lib')
local max_percent_health_redux

function healing_lib.get_conditions_needing_cure(entity)
   -- determine if the entity is suffering from a special condition and return that condition
   local conditions = {}
   local buffs = entity and entity:is_valid() and entity:get_component('stonehearth:buffs')
   if buffs then
      for condition, rest_priority in pairs(stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS) do
         if buffs:has_category_buffs(condition) then
            table.insert(conditions, condition)
         end
      end
   end

   return conditions
end

function healing_lib.get_highest_priority_condition(entity)
   local conditions = healing_lib.get_conditions_needing_cure(entity)
   table.sort(conditions, function(a, b)
      return stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS[a] > stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS[b]
   end)
   if #conditions > 0 then
      return conditions[1], stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS[conditions[1]]
   end
end

function healing_lib.get_filter_guts_health_missing(entity)
   local expendable = entity and entity:is_valid() and entity:get_component('stonehearth:expendable_resources')
   local guts, health

   if expendable then
      guts = expendable:get_value('guts')
      if guts then
         guts = math.ceil((expendable:get_max_value('guts') - guts) / stonehearth.constants.healing.FILTER_GUTS_DIVISOR)
      end
      health = expendable:get_value('health')
      if health then
         health = math.ceil((expendable:get_max_value('health') - health) / stonehearth.constants.healing.FILTER_HEALTH_DIVISOR)
      end
   end

   return guts, health
end

function healing_lib.get_healing_multiplier(healer)
   local job_component = healer:get_component('stonehearth:job')
   local job_controller = job_component and job_component:get_curr_job_controller()
   if job_controller and job_controller.get_healing_item_effect_multiplier then
      return job_controller:get_healing_item_effect_multiplier()
   end

   return 1
end

function healing_lib.get_effective_max_health_percent(entity)
   -- limits only apply to player factions, not npc factions
   local player_id = radiant.entities.get_work_player_id(entity)
   if not player_id or player_id == '' then
      return 1
   end

   local pop = stonehearth.population:get_population(player_id)
   if not pop then
      log:error('player_id "'..player_id..'" doesn\'t have a population')
   elseif pop:is_npc() then
      return 1
   end

   local attributes_component = entity:get_component('stonehearth:attributes')
   if attributes_component then
      -- we can cache the game mode limit because that doesn't change during the game
      if not max_percent_health_redux then
         local game_mode_json = stonehearth.game_creation:get_game_mode_json()
         max_percent_health_redux = game_mode_json.max_percent_health_redux or 0
      end
      local effective_max_health_percent = attributes_component:get_attribute('effective_max_health_percent', 1)
      return math.max(effective_max_health_percent, 100 - max_percent_health_redux) / 100
   end

   return 1
end

function healing_lib.filter_healing_item(item, conditions, level)
   -- just filters whether this item *can* be used to heal, not if it's the best item for it
   local consumable_data = ConsumablesLib.get_consumable_data(item)
   if consumable_data then
      -- if it requires a level to use, check that first
      if level < (consumable_data.required_level or level) then
         return false
      end

      -- we also only want to use cures *for* curing; if they don't require a cure, don't use a cure consumable
      conditions = conditions or {}
      if #conditions == 0 and consumable_data.cures_conditions and next(consumable_data.cures_conditions) then
         return false
      end

      if #conditions > 0 then
         if not consumable_data.cures_conditions then
            return false
         end
         local cures_it = false
         for _, condition in ipairs(conditions) do
            if consumable_data.cures_conditions[condition] then
               cures_it = true
               break
            end
         end
         if not cures_it then
            return false
         end
      end

      return true
   end
end

function healing_lib.rate_healing_item(item, conditions, missing_guts, missing_health, healing_multiplier)
   -- assume the filtering already happened and if there's a condition present, there's also a cure for it
   -- try to fully cure/heal if possible, then rate based on distance from full health
   local value = 0
   local consumable_data = ConsumablesLib.get_consumable_data(item)
   if consumable_data then
      local healing_constants = stonehearth.constants.healing
      local guts_healed = math.floor((consumable_data.guts_healed or 0) / healing_constants.FILTER_GUTS_DIVISOR)
      local health_healed = math.floor((consumable_data.health_healed or 0) * (healing_multiplier or 1) / healing_constants.FILTER_HEALTH_DIVISOR)
      
      -- if curing a condition, or no condition but it fully restores their guts, it's fulfilling the primary purpose
      if conditions or guts_healed >= missing_guts then
         value = 0.5
      end

      -- an extra 0.2 if it fully heals health
      if health_healed >= missing_health then
         value = value + 0.2
      end

      -- the remaining potential 0.3 is for efficiency (if guts are missing, that's all we care about; otherwise we only care about health)
      value = value + 0.3 - 0.3 * 
            (missing_guts > 0 and math.max(math.abs(guts_healed - missing_guts), healing_constants.FILTER_GUTS_MAX_DIFF) / healing_constants.FILTER_GUTS_MAX_DIFF or
            math.max(math.abs(health_healed - missing_health), healing_constants.FILTER_HEALTH_MAX_DIFF) / healing_constants.FILTER_HEALTH_MAX_DIFF)
   end

   return value
end

function healing_lib.make_healing_filter(healer, target)
   -- find an item that will actually help the target (and that the healer is skilled enough to use?)
   -- e.g., if healing is disabled due to wounds/poison/etc., only consider items that counter those debuffs
   local conditions = healing_lib.get_conditions_needing_cure(target)
   local level = healer:get_component('stonehearth:job'):get_current_job_level()
   local guts, health = healing_lib.get_filter_guts_health_missing(target)

   if not guts or not health then
      return nil
   end

   local condition_str = ''
   table.sort(conditions)
   for _, condition in ipairs(conditions) do
      condition_str = condition_str .. condition
   end

   return stonehearth.ai:filter_from_key('drink_filter', condition_str .. '|' .. level, function(item)
            return healing_lib.filter_healing_item(item, conditions, level)
         end)
end

function healing_lib.make_healing_rater(healer, target)
   -- prioritize items that are closest to maximum efficiency based on target's status
   local conditions = healing_lib.get_conditions_needing_cure(target)
   local guts, health = healing_lib.get_filter_guts_health_missing(target)
   local healing_multiplier = healing_lib.get_healing_multiplier(healer)

   return function(item)
      return healing_lib.rate_healing_item(item, conditions, guts, health, healing_multiplier)
   end
end

return healing_lib
