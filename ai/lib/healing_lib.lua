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
         local category_buffs = buffs:get_buffs_by_category(condition)
         if category_buffs then
            local condition_ranks = {}
            for _, buff in pairs(category_buffs) do
               table.insert(condition_ranks, buff:get_rank())
            end
            -- sort in descending order
            table.sort(condition_ranks, function(a, b) return a > b end)
            local entry = {
               condition = condition,
               priority = stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS[condition],
               highest_rank = condition_ranks[1],
               ranks = condition_ranks
            }
            entry.highest_priority = entry.highest_rank * entry.priority
            table.insert(conditions, entry)
         end
      end
   end
   
   table.sort(conditions, function(a, b)
      return a.highest_priority > b.highest_priority
   end)

   return conditions
end

function healing_lib.get_highest_priority_condition(entity)
   local _, condition = next(healing_lib.get_conditions_needing_cure(entity))
   if condition then
      return condition.condition, condition.highest_priority
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
      local effective_max_health_percent = attributes_component:get_attribute('effective_max_health_percent', 100)
      return math.max(effective_max_health_percent, 100 - max_percent_health_redux) / 100
   end

   return 1
end

function healing_lib.filter_healing_item(item, conditions, level)
   -- just filters whether this item *can* be used to heal, not if it's the best item for it
   local consumable_data = ConsumablesLib.get_consumable_data(item)
   if consumable_data then
      -- if it is an equipped consumable only, check that first
		if consumable_data.equipped_only then
			return false
		end
		
		-- then if it requires a level to use, check that second
      if level < (consumable_data.required_level or level) then
         return false
      end

      -- make sure it's actually a healing_item (the previous checks are faster so we do them first)
      if not radiant.entities.is_material(item, 'healing_item') then
         return false
      end

      conditions = conditions or {}
      -- we want to prioritize using cures *for* curing; if they don't require a cure, ideally don't use a cure consumable
      -- but this will be done in the rater so that we can still use items that also cure if they're the only items
      -- if #conditions == 0 and consumable_data.cures_conditions and next(consumable_data.cures_conditions) then
      --    return false
      -- end

      if #conditions > 0 then
         if not consumable_data.cures_conditions then
            -- if this item doesn't cure anything, we can use it for anything (even if it isn't very good at it)
            return true
         end

         for _, condition in ipairs(conditions) do
            local cures_rank = consumable_data.cures_conditions[condition.condition]
            if cures_rank then
               return true
               -- we're now partially treating buffs of higher ranks, so we don't care what rank it can fully cure
               -- for i = #condition.ranks, 1, -1 do
               --    if cures_rank >= condition.ranks[i] then
               --       return true
               --    end
               -- end
            end
         end

         return false
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
      if conditions and #conditions > 0 and consumable_data.cures_conditions then
         local _, this_condition = next(conditions)
         local highest_priority_condition = this_condition.highest_priority
			local highest_priority_cure = 0
         for _, condition in ipairs(conditions) do
            local cures_rank = consumable_data.cures_conditions[condition.condition]
            -- don't bother considering this condition if the cure doesn't exist or if the highest priority for it is lower than our current highest cure
            if cures_rank and condition.highest_priority > highest_priority_cure then
               if cures_rank == condition.highest_rank then
                  highest_priority_cure = math.max(highest_priority_cure, condition.highest_priority)
               elseif cures_rank > condition.highest_rank then
                  -- if it would "over-cure" (cure higher rank conditions), rate it lower by half a rank; we'd prefer to save those for the higher rank conditions
                  highest_priority_cure = math.max(highest_priority_cure, condition.priority * (condition.highest_rank - 0.5))
               else
                  -- it will partially cure, so rank it based on how much
                  highest_priority_cure = math.max(highest_priority_cure, condition.highest_priority / (2 ^ (condition.highest_rank - cures_rank)))
                  -- for i = 2, i < #condition.ranks do
                  --    if cures_rank >= condition.ranks[i] then
                  --       highest_priority_cure = math.max(highest_priority_cure, condition.priority * condition.ranks[i])
                  --       break
                  --    end
                  -- end
               end
            end
         end

         if highest_priority_cure > 0 then
            if highest_priority_condition > 0 then
               value = 0.6 * highest_priority_cure / highest_priority_condition
            else
               value = 0.6
            end
         end
      elseif guts_healed >= missing_guts then
         -- if the consumable would cure conditions, rate it down (we'd prefer to save those for actually curing conditions)
         if (not conditions or #conditions == 0) then
            -- no conditions and it doesn't cure anything: give it the full value
            if not consumable_data.cures_conditions then
               value = 0.6
            else
               -- if it cures something but we have no conditions, that's bad!
               local cures_something = false
               for _, cures_it in pairs(consumable_data.cures_conditions) do
                  if cures_it then
                     cures_something = true
                     break
                  end
               end
               if not cures_something then
                  value = 0.6
               end
            end
         end
      end

      -- an extra 0.1 if it fully heals health
      if health_healed >= missing_health then
         value = value + 0.1
      end

      -- the remaining potential 0.3 is for efficiency (if guts are missing, that's all we care about; otherwise we only care about health)
      value = value + 0.3 - 0.3 * 
            ((missing_guts > 0 and math.min(math.abs(guts_healed - missing_guts), healing_constants.FILTER_GUTS_MAX_DIFF) / healing_constants.FILTER_GUTS_MAX_DIFF) or
            (math.min(math.abs(health_healed - missing_health), healing_constants.FILTER_HEALTH_MAX_DIFF) / healing_constants.FILTER_HEALTH_MAX_DIFF))
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

   -- this potentially makes a ton of different item filters; will this negatively impact performance?
   local condition_str = ''
   for _, condition in ipairs(conditions) do
      local rank_str = tostring(condition.highest_rank)
      for i = 2, #condition.ranks do
         rank_str = rank_str .. ',' .. condition.ranks[i]
      end

      condition_str = condition_str .. condition.condition .. ':' .. rank_str .. '|'
   end

   return stonehearth.ai:filter_from_key('healing_item_filter', condition_str .. level .. '|' .. guts .. '|' .. health, function(item)
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
