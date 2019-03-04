local CombatService = require 'stonehearth.services.server.combat.combat_service'
local AceCombatService = class()

local get_player_id = radiant.entities.get_player_id

local EXP_SPLIT_AMOUNT = 0.7  -- each entity involved will get 30% of the raw exp value; 70% will be divided out among them

--AceCombatService._ace_old__on_target_killed = CombatService._on_target_killed
function AceCombatService:_on_target_killed(attacker, target)
   local attacker_player_id = get_player_id(attacker)
   local target_player_id = get_player_id(target)

   if attacker_player_id ~= target_player_id then
      local nearby_units = self:_get_nearby_units(target, attacker, attacker_player_id)
      self:distribute_exp(attacker, target, nearby_units)
      self:_notify_combat_participants(attacker, target, nearby_units)
      self:_record_kill_stats(attacker, target, nearby_units)
   end

   self:_handle_loot_drop(attacker, target)
end

-- record kill stats for killer, assistants, and killer's weapon:
--    player_id of victim, category of victim (if available), total kills/assists, and notable victim kills
function AceCombatService:_record_kill_stats(attacker, target, units)
   local enemy_player = get_player_id(target)
   local catalog_data = stonehearth.catalog:get_catalog_data(target)
   local enemy_category = catalog_data and catalog_data.category

   if enemy_player and enemy_player ~= '' then
      for _, unit in pairs(units) do
         -- for the attacker, record kills; otherwise record assists
         self:_record_kill_stats_for_entity(unit, unit == attacker and 'kills' or 'assists', enemy_player, enemy_category, true)
      end
      self:_record_notable_kill_for_entity(attacker, target)

      -- also add the stat to the attacker's weapon
      local weapon = stonehearth.combat:get_main_weapon(attacker)
      if weapon ~= nil and weapon:is_valid() then
         self:_record_kill_stats_for_entity(weapon, 'kills', enemy_player, enemy_category, true)
         self:_record_notable_kill_for_entity(weapon, target)
      end
   end
end

function AceCombatService:_record_kill_stats_for_entity(entity, category, name, enemy_category, increment_totals)
   entity:add_component('stonehearth_ace:statistics'):increment_stat(category, name)

   if enemy_category then
      entity:add_component('stonehearth_ace:statistics'):increment_stat('category_' .. category, enemy_category)
   end

   if increment_totals then
      entity:add_component('stonehearth_ace:statistics'):increment_stat('totals', category)
   end
end

function AceCombatService:_record_notable_kill_for_entity(entity, target)
   local unit_info = target:get_component('stonehearth:unit_info')
   if unit_info and unit_info:is_notable() then
      entity:add_component('stonehearth_ace:statistics'):add_to_stat_list('notable_kills', 'names', unit_info:get_custom_name(target))
   end
end

-- Split exp among attacking player's combat units
function AceCombatService:distribute_exp(attacker, target, units)

   if stonehearth.player:is_npc(attacker) then
      -- no exp for npc players
      return
   end

   local attacker_player_id = get_player_id(attacker)
   local target_player_id = get_player_id(target)

   local attributes_component = target:get_component('stonehearth:attributes')
   local exp = attributes_component:get_attribute('exp_reward') or 0 -- exp given from killing target, default is 0
   if exp == 0 then -- if target gives no exp, no need to continue
      return
   end

   -- if player's citizen killed an enemy target then reward xp to nearby combat units
   if attacker_player_id ~= target_player_id then
      -- Get all combat units that we should give xp to
      local combat_units, num_nearby_combatants = self:_get_nearby_non_max_level_combat_units(target, attacker, units)
      if num_nearby_combatants <= 0 then
         num_nearby_combatants = 1
      end
       -- TODO(yshan): SHOULD we split exp reward with all nearby combat units? We tried it and xp was too low.
       -- Paul: only split part of the exp
      exp = math.floor((1 - EXP_SPLIT_AMOUNT) * exp + EXP_SPLIT_AMOUNT * exp * num_nearby_combatants)
      for _, combat_unit in pairs(combat_units) do
         local job_component = combat_unit:get_component('stonehearth:job')
         job_component:add_exp(exp)
         radiant.events.trigger_async(combat_unit, 'stonehearth:combat_exp_awarded', {exp_awarded = exp, attacker = attacker, target = target})
      end
   end
end

function AceCombatService:_notify_combat_participants(attacker, target, units)
   for _, unit in pairs(units) do
      radiant.events.trigger_async(unit, 'stonehearth:combat_participated', { attacker = attacker, target = target })
   end
end

function AceCombatService:_get_nearby_non_max_level_combat_units(target, attacker, units)
   local count = 0
   local combat_units = {}

   for id, unit in pairs(units) do
      local job_component = unit:get_component('stonehearth:job')
      if not job_component:is_max_level() and job_component:has_role('combat') then
         combat_units[id] = unit
         count = count + 1
      end
   end

   return combat_units, count
end

return AceCombatService