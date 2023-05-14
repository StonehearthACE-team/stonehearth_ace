--[[

]]

local ConsumablesLib = require 'stonehearth.ai.lib.consumables_lib'

local healing_lib = {}

local log = radiant.log.create_logger('healing_lib')
local max_percent_health_redux

-- cache lists of healing items by conditions they cure, so the condition can be looked up and then an item tracker checked for those uris
-- also cache the uris so they easily just get indexed once
local healing_item_cache = {}
local cached_healing_item_uris = {}

function healing_lib.cache_healing_item(uri, item)
   if cached_healing_item_uris[uri] == nil then
      cached_healing_item_uris[uri] = true

      local consumable_data = ConsumablesLib.get_consumable_data(item)
      if not consumable_data or consumable_data.equipped_only then
         cached_healing_item_uris[uri] = false
         return
      end

      if consumable_data.cures_conditions then
         for condition, rank in pairs(consumable_data.cures_conditions) do
            local condition_cache = healing_item_cache[condition]
            if not condition_cache then
               condition_cache = {}
               healing_item_cache[condition] = condition_cache
            end
            condition_cache[uri] = rank
         end
      end
   end
end

function healing_lib.get_conditions_needing_cure(entity)
   -- determine if the entity is suffering from a special condition and return that condition
   local conditions = {}
   local buffs = entity and entity:is_valid() and entity:get_component('stonehearth:buffs')
   if buffs then
      local special_conditions = stonehearth.constants.healing.SPECIAL_ATTENTION_CONDITIONS
      for condition, rest_priority in pairs(special_conditions) do
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
               priority = special_conditions[condition],
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

function healing_lib.cure_conditions(target, cures_conditions, reduce_rank)
   local buffs_component = target:get_component('stonehearth:buffs')
   if buffs_component and cures_conditions then
      for condition, cures_rank in pairs(cures_conditions) do
         if cures_rank then
            -- default to reducing rank if not enough to cure
            buffs_component:remove_category_buffs(condition, cures_rank, reduce_rank ~= false)
         end
      end
   end
end

function healing_lib.heal_target(healer, target, health, guts)
   if radiant.entities.get_health(target) > 0 then
      if health and health ~= 0 then
         local healed_amount = health * healing_lib.get_healing_multiplier(healer)

         radiant.entities.modify_health(target, healed_amount, healer)
      end
   else
      local guts_healed = guts or 1
      if guts_healed ~= 0 then
         radiant.entities.modify_resource(target, 'guts', guts_healed)
      end
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

function healing_lib.filter_healing_item(item, conditions, level, guts, health)
   -- just filters whether this item *can* be used to heal, not if it's the best item for it
   local uri = item:get_uri()
   -- if the healing_item_tracker isn't caching these before this gets called, we'll have a problem
   if not cached_healing_item_uris[uri] then
      return false
   end

   local consumable_data = ConsumablesLib.get_consumable_data(item)
   -- if it requires a level to use, check that
   if level and level < (consumable_data.required_level or level) then
      return false
   end

   conditions = conditions or {}
   if #conditions == 0 then
      -- if there are no conditions, we only care about consumables that give needed guts/health
      if guts > 0 then
         return (consumable_data.guts_healed or 0) > 0
      else
         return health > 0 and (consumable_data.health_healed or 0) > 0
      end
   else
      if not consumable_data.cures_conditions then
         -- if this item doesn't cure anything, we can use it for anything (it probably heals or applies a beneficial effect)
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

function healing_lib.rate_healing_item(item, conditions, missing_guts, missing_health, healing_multiplier)
   -- assume the filtering already happened and if there's a condition present, there's also a cure for it
   -- try to fully cure/heal if possible, then rate based on distance from full health
   local value = 0
   local consumable_data = ConsumablesLib.get_consumable_data(item)
   if consumable_data then
      local healing_constants = stonehearth.constants.healing
      local guts_healed = math.floor((consumable_data.guts_healed or 0) / healing_constants.FILTER_GUTS_DIVISOR)
      local health_healed = math.floor((consumable_data.health_healed or 0) * (healing_multiplier or 1) / healing_constants.FILTER_HEALTH_DIVISOR)
      local avoids_recently_treated_factor = healing_constants.healing_item_factors.AVOIDS_RECENTLY_TREATED
      local condition_factor = healing_constants.healing_item_factors.CONDITION
      local special_priority_factor = healing_constants.healing_item_factors.SPECIAL_PRIORITY
      local full_heal_factor = healing_constants.healing_item_factors.FULL_HEAL
      local percent_heal_factor = healing_constants.healing_item_factors.PERCENT_HEAL
      
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
               value = condition_factor * highest_priority_cure / highest_priority_condition
            else
               value = condition_factor
            end
         end
      elseif missing_guts > 0 and guts_healed >= missing_guts then
         -- if the consumable would cure conditions, rate it down (we'd prefer to save those for actually curing conditions)
         if (not conditions or #conditions == 0) then
            -- no conditions and it doesn't cure anything: give it the full value
            if not consumable_data.cures_conditions then
               value = condition_factor
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
                  value = condition_factor
               end
            end
         end
      end

      -- healing efficiency (if guts are missing, that's all we care about; otherwise we only care about health)
      value = value + percent_heal_factor - percent_heal_factor * 
            ((missing_guts > 0 and math.min(math.abs(guts_healed - missing_guts), healing_constants.FILTER_GUTS_MAX_DIFF) / healing_constants.FILTER_GUTS_MAX_DIFF) or
            (math.min(math.abs(health_healed - missing_health), healing_constants.FILTER_HEALTH_MAX_DIFF) / healing_constants.FILTER_HEALTH_MAX_DIFF))

      -- an extra bit if it fully heals health
      if missing_health > 0 and health_healed >= missing_health then
         value = value + full_heal_factor
      end

      -- don't give a special priority or recently treated remover bonus if it doesn't even do anything needed in the first place
      if value == 0 then
         return 0
      end

      local special_priority = consumable_data.special_priority
      if special_priority then
         value = value + special_priority_factor * (1 + math.min(1, math.max(-1, special_priority))) * 0.5
      end

      -- whether it applies the buff that removes the recently treated debuff (allowing subsequent healing items to be applied)
      local avoids_recently_treated = consumable_data.applies_effects and consumable_data.applies_effects['stonehearth_ace:buffs:recently_treated:remover']
      if avoids_recently_treated then
         -- based on the percent chance that it applies the effect
         value = value + avoids_recently_treated_factor * math.min(1, math.max(0, avoids_recently_treated))
      end
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
            return healing_lib.filter_healing_item(item, conditions, level, guts, health)
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
