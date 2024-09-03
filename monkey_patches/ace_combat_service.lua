local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local CombatService = require 'stonehearth.services.server.combat.combat_service'
local AceCombatService = class()

local log = radiant.log.create_logger('combat_service')

local get_player_id = radiant.entities.get_player_id

local EXP_SPLIT_AMOUNT = 0.7  -- each entity involved will get 30% of the raw exp value; 70% will be divided out among them
local BASIC_SIEGE_DAMAGE = 0.4  -- how much of their total damage (in %) will non siege-specific units perform against siege objects
-- ACE: EXP_WEIGHT constants are used by the automatic calculation of awarded experience based on the defeated target's stats
local MUSCLE_EXP_WEIGHT = stonehearth.constants.exp.MUSCLE_EXP_WEIGHT or 4
local COURAGE_EXP_WEIGHT = stonehearth.constants.exp.COURAGE_EXP_WEIGHT or 1
local SPEED_EXP_WEIGHT = stonehearth.constants.exp.SPEED_EXP_WEIGHT or 0.5
local ARMOR_EXP_WEIGHT = stonehearth.constants.exp.ARMOR_EXP_WEIGHT or 8
local DMG_EXP_WEIGHT = stonehearth.constants.exp.DMG_EXP_WEIGHT or 10
local RETREATING_BUFF = 'stonehearth_ace:buffs:retreating'
local SOFT_RETREATING_BUFF = 'stonehearth_ace:buffs:retreating:soft'

-- Notify target that it has been hit by an attack.
-- ACE: include damage source when modifying health
function AceCombatService:battery(context)
   local attacker = context.attacker
   local target = context.target

   if not target or not target:is_valid() then
      return nil
   end

   local health = radiant.entities.get_health(target)
   local health_percent = radiant.entities.get_health_percentage(target)
   local damage = context.damage
   -- for leash purposes, we care more about the primary target than the attacker of this specific battery
   local enemy = self:get_primary_target(target) or attacker

   if stonehearth.player:is_npc(target) and self:has_leash(target) and not stonehearth.player:is_npc(enemy) and self:get_main_weapon(target) then
      if health_percent < 0.5 then
         if self:is_leash_unbreakable(target) then
            radiant.entities.add_buff(target, SOFT_RETREATING_BUFF) -- Don't just stand there! Go back to your place!
         else
            self:clear_leash(target) -- This is probably a legit fight, let it roll...
         end
      else
         -- if we're outside our leash, we should retreat, unless we're panicking, in which case it's pointless to have a leash anymore
         -- if we don't have a main weapon we're not a fighter and we shouldn't bother about being exploited (i.e.: huntable animals)
         -- if we're inside our leash and our primary target is outside the leash and isn't in range, we should retreat
         -- this is a bit of a cheap hack because we're not bothering to find if there is a location within the leash where we could attack
         -- only if we're already in range; but with a reasonably large leash, this should be good enough, and is a lot faster
         -- don't need to worry about line of sight since they're not going to get attacked by a target that doesn't have line of sight on them
         if self:is_entity_outside_leash(target) then
            if self:panicking(target) then
               self:clear_leash(target) -- Run to the hills! Run for your lives!
            else
               radiant.entities.add_buff(target, SOFT_RETREATING_BUFF) -- Suspicious, retreat!
            end
         else
            local weapon = self:get_main_weapon(target)
            if self:is_point_outside_leash(target, radiant.entities.get_world_grid_location(enemy)) and
                  not self:in_range(target, enemy, weapon) then
               radiant.entities.add_buff(target, RETREATING_BUFF) -- Stop exploiting!
            end
         end
      end
   end

   if health ~= nil then
      if health <= 0 then
      -- if monster is already at/below 0 health, it should be considered dead so don't continue battery
         return nil
      end
      health = health - damage
      if health <= 0 then
         self:_on_target_killed(attacker, target)
      end

      -- Modify health after distributing xp and removing components,
      -- so it does not kill the entity before we have a chance to do that
      radiant.entities.modify_health(target, -damage, attacker)
   end

   radiant.events.trigger_async(attacker, 'stonehearth:combat:target_hit', context)
   radiant.events.trigger_async(target, 'stonehearth:combat:battery', context)
end

function AceCombatService:_calculate_damage(attacker, target, attack_info, base_damage_name)
   local weapon = stonehearth.combat:get_main_weapon(attacker)

   if not weapon or not weapon:is_valid() then
      return 0
   end

   local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
   local base_damage = weapon_data[base_damage_name]

   if not base_damage then
      return 0
   end

   local total_damage = base_damage
   local attributes_component = attacker:get_component('stonehearth:attributes')
   if not attributes_component then
      return total_damage
   end
   local additive_dmg_modifier = attributes_component:get_attribute('additive_dmg_modifier')
   local multiplicative_dmg_modifier = attributes_component:get_attribute('multiplicative_dmg_modifier')
   local muscle = attributes_component:get_attribute('muscle')

   -- ACE: Ignore this part if the weapon's custom value for muscle influence on damage is 0
   if muscle and weapon_data.muscle_multiplier ~= 0 then
      local muscle_dmg_modifier = muscle * stonehearth.constants.attribute_effects.MUSCLE_MELEE_MULTIPLIER
      muscle_dmg_modifier = muscle_dmg_modifier + stonehearth.constants.attribute_effects.MUSCLE_MELEE_MULTIPLIER_BASE
      -- ACE: Allow for weapons to have a custom value for the muscle influence on damage
      if weapon_data.muscle_multiplier then
         muscle_dmg_modifier = muscle_dmg_modifier * weapon_data.muscle_multiplier
      end
      additive_dmg_modifier = additive_dmg_modifier + muscle_dmg_modifier
   end

   if multiplicative_dmg_modifier then
      local dmg_to_add = base_damage * multiplicative_dmg_modifier
      total_damage = dmg_to_add + total_damage
   end
   if additive_dmg_modifier then
      total_damage = total_damage + additive_dmg_modifier
   end

   --Get damage from weapons
   if attack_info.damage_multiplier then
      total_damage = total_damage * attack_info.damage_multiplier
   end

   --Get the damage reduction from armor
   local total_armor = self:calculate_total_armor(target)

   -- Reduce armor if attacker has armor reduction attributes
   local multiplicative_target_armor_modifier = attributes_component:get_attribute('multiplicative_target_armor_modifier', 1)
   local additive_target_armor_modifier = attributes_component:get_attribute('additive_target_armor_modifier', 0)

   if attack_info.target_armor_multiplier then
      multiplicative_target_armor_modifier = multiplicative_target_armor_modifier * attack_info.target_armor_multiplier
   end

   total_armor = total_armor * multiplicative_target_armor_modifier + additive_target_armor_modifier

   local damage = total_damage - total_armor

   -- ACE: Cover siege damage
   if self:is_killable_target_of_type(target, 'siege') then
      local ec = attacker:get_component('stonehearth:equipment')
      if ec and ec:has_item_type('stonehearth_ace:abilities:basic_door_breaker_abilities') then
         damage = math.max(1, damage * BASIC_SIEGE_DAMAGE)
      end
   end

   if attack_info.minimum_damage and damage <= attack_info.minimum_damage then
      damage = attack_info.minimum_damage
   elseif damage < 1 then
      --[[ ACE: Let's not do this for now until we go over all enemy stats
      -- ACE: Make it so instead of randomly dealing 1 or 0, it will instead deal it based on how close to 1 or 0 it is
      if rng:get_real(0,1) <= damage then
         damage = 1
      else
         damage = 0
      end
      ]]
      damage = rng:get_int(0, 1)
   else
      -- ACE: Leave rounding for last, if no other rules apply, for when we go back to the other method
      damage = radiant.math.round(damage)
   end

   return damage
end

AceCombatService._ace_old_calculate_healing = CombatService.calculate_healing
function AceCombatService:calculate_healing(healer, target, heal_info)
   local total_healing = self:_ace_old_calculate_healing(healer, target, heal_info)

   local attributes_component = target:get_component('stonehearth:attributes')
   if attributes_component then
      local additive_heal_modifier = attributes_component:get_attribute('additive_heal_received_modifier')
      local multiplicative_heal_modifier = attributes_component:get_attribute('multiplicative_heal_received_modifier')

      if multiplicative_heal_modifier then
         total_healing = total_healing + total_healing * multiplicative_heal_modifier
      end
      if additive_heal_modifier then
         total_healing = total_healing + additive_heal_modifier
      end

      total_healing = radiant.math.round(total_healing)
   end

   return total_healing
end

function AceCombatService:calculate_exp_reward(target)
   local exp = 0

   if target and target:is_valid() then
      local attributes_component = target:get_component('stonehearth:attributes')
      if attributes_component:has_attribute('exp_reward_override') then
         return attributes_component:get_attribute('exp_reward_override')
      end

      local max_health = attributes_component:get_attribute('max_health')^2 / 100
      local muscle = attributes_component:get_attribute('muscle') * MUSCLE_EXP_WEIGHT
      local courage = attributes_component:get_attribute('courage') * COURAGE_EXP_WEIGHT
      local speed = attributes_component:get_attribute('speed') * SPEED_EXP_WEIGHT
      local additive_armor_modifier = attributes_component:get_attribute('additive_armor_modifier') * ARMOR_EXP_WEIGHT
      local multiplicative_dmg_modifier = attributes_component:get_attribute('multiplicative_dmg_modifier') * DMG_EXP_WEIGHT

      exp = math.floor(math.sqrt(max_health + muscle + courage + speed + additive_armor_modifier + multiplicative_dmg_modifier) + 0.5)
   end

   return exp
end

-- ACE: also get allies of the attacker
function AceCombatService:_get_nearby_units(target, attacker, player_id)
   local radius = stonehearth.constants.exp.EXP_REWARD_RADIUS
   local enemy_location = radiant.entities.get_world_grid_location(target)
   local ally_location = radiant.entities.get_world_grid_location(attacker)

   local units = {}
   local count = 0

   -- check all citizens in population of player *and friendly players* and return all combats units within the radius
   local friendly_players = stonehearth.player:get_friendly_players(player_id)
   for friendly_player, _ in pairs(friendly_players) do
      local population = stonehearth.population:get_population(friendly_player)
      if population then
         for id, citizen in population:get_citizens():each() do
            if citizen and citizen:is_valid() then
               local job_component = citizen:get_component('stonehearth:job')
               -- should the citizen be counted as participating?

               local location = radiant.entities.get_world_grid_location(citizen)
               -- Allow unit to participate if the combat unit is in range of the enemy or allied attacker OR
               -- the combat unit has the enemy in its target table -> ranged attackers may be far away but
               -- still may have contributed to killing the target.
               if location then
                  local target_table = radiant.entities.get_target_table(citizen, 'aggro')
                  if (target_table and target_table:contains(target)) or
                     radiant.math.point_within_sphere(location, enemy_location, radius) or
                     radiant.math.point_within_sphere(location, ally_location, radius) then
                     units[id] = citizen
                     count = count + 1
                  end
               end
            end
         end
      end
   end

   return units, count
end

--AceCombatService._ace_old__on_target_killed = CombatService._on_target_killed
function AceCombatService:_on_target_killed(attacker, target)
   local attacker_player_id = get_player_id(attacker)
   local target_player_id = get_player_id(target)

   if attacker_player_id ~= target_player_id then
      local nearby_units = self:_get_nearby_units(target, attacker, attacker_player_id)
      self:distribute_exp(attacker, target, nearby_units)
      self:_notify_combat_participants(attacker, target, nearby_units)

      if radiant.entities.has_free_will(target) then
         self:_record_kill_stats(attacker, target, nearby_units)
      end
   end

   self:_queue_killed_entity_craft_order(target)
   self:_handle_loot_drop(attacker, target)
end

function AceCombatService:_queue_killed_entity_craft_order(entity)
   local player_id = get_player_id(entity)
   local job_controller = stonehearth.job:get_jobs_controller(player_id)
   if job_controller then
      local auto_craft = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'auto_craft_killed_items', true)
      if auto_craft then
         job_controller:request_craft_product(entity:get_uri(), 1)
      end
   end
end

-- record kill stats for killer, assistants, and killer's equipment:
--    player_id of victim, category of victim (if available), total kills/assists, and notable victim kills
function AceCombatService:_record_kill_stats(attacker, target, units)
   local enemy_player = get_player_id(target)

   if enemy_player and enemy_player ~= '' then
      local catalog_data = stonehearth.catalog:get_catalog_data(target:get_uri())
      local enemy_category = catalog_data and catalog_data.category
      local enemy_specifier = radiant.entities.get_property_value(target, 'stats_specifier')

      for _, unit in pairs(units) do
         -- for the attacker, record kills; otherwise record assists
         -- only record assists for hearthlings that are in a combat stance
         local stance = self:get_stance(unit)
         if stance == 'defensive' or stance == 'aggressive' then
            self:_record_kill_stats_for_entity(unit, unit == attacker and 'kills' or 'assists', enemy_player, enemy_category, enemy_specifier, true)
         end
      end
      self:_record_notable_kill_for_entity(attacker, target)

      -- also add the stat to the attacker's equipment
      local equipment = attacker:get_component('stonehearth:equipment')
      if equipment then
         for _, piece in pairs(equipment:get_all_items()) do
            self:_record_kill_stats_for_entity(piece, 'kills', enemy_player, enemy_category, enemy_specifier, true)
            self:_record_notable_kill_for_entity(piece, target)
         end
      end
   end
end

function AceCombatService:_record_kill_stats_for_entity(entity, category, name, enemy_category, enemy_specifier, increment_totals)
   local stats_comp = entity:get_component('stonehearth_ace:statistics')

   if stats_comp then
      stats_comp:increment_stat(category, name)

      if enemy_category then
         stats_comp:increment_stat('category_' .. category, enemy_category)
      end

      if enemy_specifier then
         stats_comp:increment_stat('specific_' .. category, enemy_specifier)
      end

      if increment_totals then
         stats_comp:increment_stat('totals', category)
      end
   end
end

function AceCombatService:_record_notable_kill_for_entity(entity, target)
   local stats_comp = entity:get_component('stonehearth_ace:statistics')
   if stats_comp then
      local is_notable = radiant.entities.get_property_value(target, 'notable')
      if is_notable then
         stats_comp:add_to_stat_list('notable_kills', 'names', radiant.entities.get_custom_name(target))
      end
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

   -- (ACE) For sanity reasons and to not go over a menagerie of monsters to replace completely arbritary values given over years, we want Exp to be calculated by logic from now on; it can still be manually assigned with 'exp_reward_override' attribute.
   local exp = self:calculate_exp_reward(target)
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
      exp = math.floor((1 - EXP_SPLIT_AMOUNT) * exp + EXP_SPLIT_AMOUNT * exp / num_nearby_combatants)
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
      if job_component and not job_component:is_max_level() and job_component:has_role('combat') then
         combat_units[id] = unit
         count = count + 1
      end
   end

   return combat_units, count
end

-- ACE: also include support for shared cooldowns
function AceCombatService:start_cooldown(entity, action_info)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return
   end
   combat_state:start_cooldown(action_info.name, action_info.cooldown)

   if action_info.shared_cooldown_name then
      combat_state:start_cooldown(action_info.shared_cooldown_name, action_info.shared_cooldown)
   end
end

function AceCombatService:in_cooldown(entity, action_name, shared_cooldown_name)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return false
   end

   return combat_state:in_cooldown(action_name, shared_cooldown_name)
end

function AceCombatService:get_cooldown_end_time(entity, action_name, shared_cooldown_name)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return nil
   end

   return combat_state:get_cooldown_end_time(action_name, shared_cooldown_name)
end

-- get the highest priority action that is ready now
-- assumes actions are sorted by descending priority
-- ACE: modifies filter_fn to consider any required equipment types
function AceCombatService:choose_attack_action(entity, actions)
   local filter_fn = function(combat_state, action_info)
      log:debug('considering choosing attack action %s...', action_info.name)
      if not combat_state:in_cooldown(action_info.name, action_info.shared_cooldown_name) then
         -- check any equipment requirements
         if action_info.required_equipment then
            for slot, types in pairs(action_info.required_equipment) do
               local item = radiant.entities.get_equipped_item(entity, slot)
               local ep = item and item:add_component('stonehearth:equipment_piece')
               -- types is specified as an array of types, any one of which is acceptable
               local wants_no_item = not next(types) or (#types == 1 and types[1] == '')

               -- if there is an item equipped there, but there shouldn't be, or vice-versa
               if (ep and wants_no_item) or (not ep and not wants_no_item) then
                  return false
               end

               -- check if any of these types is present
               local found_type = false
               for _, eq_type in ipairs(types) do
                  -- if it allows for nothing equipped here and that's the case
                  -- or if it requires a specific type equipped and that's the case
                  if (not ep and eq_type == '') or (ep and ep:is_type(eq_type)) then
                     found_type = true
                     break
                  end
               end
               -- if it didn't find a valid type, it was no good
               -- we only return false early: true will get returned later if all conditions are met
               if not found_type then
                  return false
               end
            end
         end

         return true
      end
   end
   return self:_choose_combat_action(entity, actions, filter_fn)
end

-- get the highest priority action that can take effect before the impact_time
-- assumes actions are sorted by descending priority
-- ACE: add support for shared cooldowns
function AceCombatService:choose_defense_action(entity, actions, attack_impact_time)
   local filter_fn = function(combat_state, action_info)
      local ready_time = combat_state:get_cooldown_end_time(action_info.name, action_info.shared_cooldown_name) or radiant.gamestate.now()
      local defense_impact_time = ready_time + action_info.time_to_impact
      return defense_impact_time <= attack_impact_time
   end
   return self:_choose_combat_action(entity, actions, filter_fn)
end

-- ACE: include attacker with the debuffs
function AceCombatService:inflict_debuffs(attacker, target, attack_info)
   local inflictable_debuffs = self:get_inflictable_debuffs(attacker, attack_info)
   self:try_inflict_debuffs(target, inflictable_debuffs, attacker)
end

-- Adds resistance to wounds
function AceCombatService:try_inflict_debuffs(target, debuff_list, attacker)
   local attributes = target:get_component('stonehearth:attributes')
	local debuff_resistance = attributes and attributes:get_attribute('debuff_resistance') or 0
   for _, debuff_data in ipairs(debuff_list) do
      for name, debuff in pairs(debuff_data) do
         local infliction_chance = debuff.chance or 1
         local n = 100 * infliction_chance
         local i = rng:get_int(1,100)
			if debuff.resistable and debuff_resistance ~= 0 then
				i = i + (debuff_resistance * 100)
			end
         if i <= n then
            target:add_component('stonehearth:buffs'):add_buff(debuff.uri, {
               source = attacker,
               source_player = attacker:get_player_id()
            })
         end
      end
   end
end

function AceCombatService:apply_buffs(entity, target, ability_info)
   local buffs = self:get_appliable_buffs(entity, ability_info, entity == target)
   -- this function will check debuff_resistance, but that shouldn't be specified for any of these buffs
   -- so no reason to duplicate the function as an "apply_buffs" function
   stonehearth.combat:try_inflict_debuffs(target, buffs, entity)
end

function AceCombatService:get_appliable_buffs(entity, ability_info, is_self_buff)
   local entity_data = radiant.entities.get_entity_data(entity, 'stonehearth:buffs')
   local buff_list = {}
   local buff_type = is_self_buff and 'appliable_self_buffs' or 'appliable_target_buffs'
   if entity_data and entity_data[buff_type] then
      table.insert(buff_list, entity_data[buff_type])
   end
   if ability_info and ability_info[buff_type] then
      table.insert(buff_list, ability_info[buff_type])
   end

   local equipment_component = entity:get_component('stonehearth:equipment')
   if equipment_component then
      -- Look through all equipment to see if any equipment can inflict debuffs
      local items = equipment_component:get_all_items()

      for _, item in pairs(items) do
         local item_buff_data = radiant.entities.get_entity_data(item, 'stonehearth:buffs')
         if item_buff_data and item_buff_data[buff_type] then
            table.insert(buff_list, item_buff_data[buff_type])
         end
      end
   end

   return buff_list
end

-- allow specifying locations for attack and target
function AceCombatService:has_potential_line_of_sight(attacker, target, attacker_location, target_location)
   local result = _physics:has_line_of_sight(attacker, target, attacker_location, target_location)
   return result
end

-- changed to take elevation into account, and allow specifying locations for attack and target
function AceCombatService:in_range(attacker, target, weapon, attacker_location, target_location)
   if not (target and target:is_valid()) then
      return false
   end

   attacker_location = attacker_location or attacker:add_component('mob'):get_world_grid_location()
   target_location = target_location or target:add_component('mob'):get_world_grid_location()
   if not (attacker_location and target_location) then
      return false
   end

   local weapon_data = weapon and radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data') or {}
   local range = weapon_data.range

   if range then
      range = self:get_weapon_range(attacker, weapon)
   else
      range = weapon_data.reach or 1
   end

   return self:location_in_range(attacker_location, target_location, range)
end

function AceCombatService:location_in_range(attacker_location, target_location, range)
   -- weapon range is at same elevation
   -- R*sqrt(1+2*h/R), where R is normal weapon range and h is height difference
   local elevation_factor = attacker_location.y - target_location.y
   if elevation_factor >= 0.5 * range then
      return false
   end

   local adjusted_range = range * math.sqrt(1 + 2 * elevation_factor / range)

   local distance = Point3(attacker_location.x, 0, attacker_location.z):distance_to(Point3(target_location.x, 0, target_location.z))
   local result = distance <= adjusted_range
   return result
end

function AceCombatService:set_leash(entity, center, range, unbreakable)
   local combat_state = self:get_combat_state(entity)
   if not combat_state then
      return
   end
   combat_state:_set_leash(center, range, unbreakable)
end

function AceCombatService:is_leash_unbreakable(entity)
   local leash_data = self:get_leash_data(entity)
   return leash_data and leash_data.unbreakable
end

return AceCombatService