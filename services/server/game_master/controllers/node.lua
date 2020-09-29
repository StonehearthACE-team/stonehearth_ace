local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local Node = class()

local RARITY_VOTES = {
   common = 100,
   rare   = 50,
}

function Node:has_dynamic_sv()
   -- Tells the persistence system to set our save data directly instead of using an sv table
   return true
end

function Node:initialize()
   self._sv.json_path = nil
   self._sv.game_master = nil
   self._log = radiant.log.create_logger(self:get_log_name())
end

function Node:create(json_path, game_master)
   self._sv.json_path = json_path
   self._sv.game_master = game_master
end

function Node:restore()
   -- Nodes created before we added the game master reference are single-player.
   if not self._sv.game_master then
      self._sv.game_master = stonehearth.game_master:get_game_master('player_1')
   end
end

function Node:activate()
   self:load_json()
end

function Node:destroy()
   if self._sv.ctx then
      self._sv.ctx:destroy()
      self._sv.ctx = nil
   end
   self.__saved_variables:mark_changed()
end

function Node:suspend()
   
end

function Node:continue()
   
end

-- set the name of the node.  all nodes in a single nodelist must have unique
-- names
--
function Node:set_name(name)
   self._sv.name = name
   self.__saved_variables:mark_changed()
   return self
end

function Node:get_node_name()
   return self._sv.node_name
end

-- create a child nodelist of this node given the specified `list` data, which
-- is a table containing name to node-info file mappings.
--
function Node:_create_nodelist(expected_type, list)
   assert(type(list) == 'table', 'invalid nodelist passed to create_nodelist')
   local ctx = self._sv.ctx or self._sv.game_master._sv.ctx
   return radiant.create_controller('stonehearth:game_master:node_list', ctx.player_id, self._sv.name, expected_type, list)
end

-- xxx: consider moving everything below to a different class

-- get the subtype of the node (e.g. an encounter node might have a subtype
-- of 'create_camp' or 'collection_quest')
--
function Node:get_subtype()
   assert(self._sv._info)
   return self._sv._info.subtype
end

-- get the rarity of the node
--
function Node:get_rarity()
   assert(self._sv._info)
   return self._sv._info.rarity
end

-- get the number of votes this node gets during the election
--
function Node:get_vote_count()
   local rarity = self:get_rarity() or 'common'
   return RARITY_VOTES[rarity] or 1
end

-- return whether or not the encounter is unique (i.e. cannot have more than 1 running instance)
--
function Node:get_is_unique()
   assert(self._sv._info)
   return self._sv._info.unique
end

function Node:check_requirement_met(ctx, name, rule)
   local lhs
   local item, rhs, typ = rule.item, rule.value, rule.type

   self._log:info('checking can_start rule \"%s\" (type:%s item:%s value:%s)', name, tostring(typ), tostring(item), tostring(rhs))

   if not item then
      self._log:error('missing item field in can_start check.')
      return true
   end

   local ignore_req = self._sv.game_master:get_ignore_start_requirements()
   -- return true if we are debugging and we want to ignore checking this type of item or checks in general
   if ignore_req == item or ignore_req == true then
      return true -- return true if we are debugging and explicitly want to ignore these checks
   end

   -- grab the lhs...
   if item == 'kingdom' then
      lhs = stonehearth.player:get_kingdom(ctx.player_id)
   -- TODO: replace these items with score
   elseif item == 'net_worth' then
      lhs = stonehearth.player:get_net_worth(ctx.player_id) or 0
   elseif item == 'score' then
      local score_type = rule.score_type
      if not score_type then
         self._log:error('missing score_type field for score check')
         return true
      end

      local scores = stonehearth.score:get_scores_for_player(ctx.player_id):get_score_data()
      if not scores then
         self._log:info('player does not have a scores data at all while looking up %s score. returning 0', score_type)
         lhs = 0
      elseif not scores.total_scores:contains(score_type) then
         self._log:info('%s score not found in player scores. returning 0', score_type)
         lhs = 0
      else
         lhs = scores.total_scores:get(score_type)
      end
   elseif item == 'num_citizens' then
      local population = stonehearth.population:get_population(ctx.player_id)
      lhs = population:get_citizen_count() or 0
   elseif item == 'days_elapsed' then
      lhs = stonehearth.calendar:get_elapsed_days()
   elseif item == 'reached_citizen_cap' then
          --Don't spawn if we have more than tuned max people
      local num_citizens = stonehearth.population:get_population_size(ctx.player_id)
      local max_citizens = radiant.util.get_config('max_citizens', 30)
      lhs = num_citizens >= max_citizens
   elseif item == 'biome' then
      lhs = stonehearth.world_generation:get_biome_alias()
   elseif item == 'game_mode' then
      lhs = stonehearth.game_creation:get_game_mode()
   elseif item == 'hostility' then
      lhs = stonehearth.player:are_player_ids_hostile(ctx.player_id, ctx.npc_player_id)
   elseif item == 'time_of_day' then
      local hour = stonehearth.calendar:get_time_and_date().hour
      local minute = stonehearth.calendar:get_time_and_date().minute
      lhs = hour + (minute / 60)
   elseif item == 'exists_in_world' then
      local uri = rule.uri
      if not uri then
         self._log:error('missing uri for has_item check')
         return true
      end
      lhs = false
      local inventory = stonehearth.inventory:get_inventory(ctx.player_id)
      local matching = inventory and inventory:get_items_of_type(uri)
      if matching and matching.items then
         for uri, entity in pairs(matching.items) do
            if radiant.entities.exists_in_world(entity) then
               lhs = true
               break
            end
         end
      end
   elseif item == 'campaign_completed' then
      if not rule.campaign_name then
         self._log:error('missing campaign_name field for campaign completed check')
         return true
      end
      lhs = self._sv.game_master:is_campaign_completed(rule.campaign_name)
   elseif item == "script" then
      -- filter by script passed in through rule.script
      if not rule.script then
         self._log:error('missing script field for script item check')
         return true
      end
      local info = self._sv._info
      local etype = info.encounter_type
      local einfo = info[etype .. '_info']

      local script = radiant.mods.load_script(rule.script)
      lhs = script:start(ctx, einfo)
   elseif item == 'number_active' then
      -- filter by how many of these nodes are currently active on the map
      -- must specify an 'end_node' that indicates when an encounter can be considered inactive
      if not rule.end_node then
         self._log:error('missing end_node field for number_active item check')
         return true
      end

      -- Need to get the arc ctx in order to check all arc_encounters
      local arc_ctx = ctx.arc._sv.ctx

      local start_node_name = rule.start_node or self._sv._info.in_edge
      local num_spawned = arc_ctx.arc_encounters[start_node_name] or 0
      local num_finished = arc_ctx.arc_encounters[rule.end_node] or 0
      lhs = num_spawned - num_finished
   elseif item == 'number_spawned' then
      if not rule.node_name then
         self._log:error('missing node_name field for number_spawned item check')
         return true
      end

      local arc_ctx = ctx.arc._sv.ctx
      lhs = arc_ctx.arc_encounters[rule.node_name] or 0
   elseif item == 'city_tier' then
      local population = stonehearth.population:get_population(ctx.player_id)
      lhs = population:get_city_tier() or 0
   elseif item == 'highest_job_level' then
      local job = stonehearth.job:get_job_info(ctx.player_id, rule.job_alias)
      lhs = job:get_highest_level()
   elseif item == 'config' then
      if not type(rule.key) == 'string' then
         self._log:error('missing key field with string value for config check')
         return true
      end
      local value = radiant.util.get_config(rule.key)
      lhs = value
   elseif item == 'counter' then
      if not type(rule.key) == 'string' then
         self._log:error('missing key field with string value for counter check')
         return true
      end
      lhs = ctx.campaign:get_counter_value(rule.key)
   elseif item == 'weather' then
      local weather_state = stonehearth.weather:get_current_weather()
      lhs = weather_state and weather_state:get_uri()
   elseif item == 'alpha_version' then
      local alpha = _radiant.sim.get_product_minor_version()
      -- alpha 2 is the default minor version assigned in the dev environment
      lhs = alpha == 2 or alpha == 20
   elseif item == 'and' then
      local and_rules = rule.tests
      lhs = self:_all_rules_pass(ctx, and_rules)
   elseif item == 'or' then
      local or_rules = rule.tests
      lhs = self:_any_rules_pass(ctx, or_rules)
   elseif item == 'none' then
      -- this is useful for modders who want to remove tests
      return true
   else
      self._log:error('unknown item \"%s\" in can_start check.', item)
      return true
   end

   -- compare against rhs based on deny rule.
   local matches
   if typ == 'deny_if' then
      return not (lhs == rhs)
   elseif typ == 'deny_if_not' then
      return not (lhs ~= rhs)
   elseif typ == 'deny_if_less_than' then
      return not (lhs < rhs)
   elseif typ == 'deny_if_greater_than' then
      return not (lhs > rhs)
   elseif typ == 'deny_if_between' then
      return not (lhs >= rhs.min and lhs <= rhs.max)
   elseif typ == 'deny_if_not_between' then
      return not (lhs < rhs.min or lhs > rhs.max)
   else
      self._log:error('unknown check type \"%s\" in can_start check.', tostring(typ))
   end

   return true;
end

-- A test is a set of rules. Every rule must pass for the test to pass
function Node:_all_rules_pass(ctx, can_start_rules)
   for name, rule in pairs(can_start_rules) do
      if not self:check_requirement_met(ctx, name, rule) then
         self._log:info('check failed for %s!  node cannot start', name)
         return false
      end
   end
   return true
end

-- A test is a set of rules. Every rule must pass for the test to pass
-- A test_set is a set of tests. Only one of the tests must pass for the test set to pass.
function Node:_any_test_set_passes(ctx, test_set)
   local passes = true
   for name, test in pairs(test_set) do
      passes = false
      if self:_all_rules_pass(ctx, test) then
         self._log:info('check success! Or set passes!')
         passes = true
         break
      end
   end
   return passes
end

-- At least one rule must pass for the test to pass
function Node:_any_rules_pass(ctx, can_start_rules)
   for name, rule in pairs(can_start_rules) do
      if self:check_requirement_met(ctx, name, rule) then
         return true
      end
   end
   return false
end

-- should the node spawn now?
function Node:can_start(ctx)
   assert(self._sv._info)

   local tests = self._sv._info.can_start
   local in_edge = self._sv._info.in_edge

   -- See if game mode has an override
   local game_mode_json = stonehearth.game_creation:get_game_mode_json()
   local encounter_tuning_overrides = game_mode_json and game_mode_json.encounter_tuning_overrides
   if encounter_tuning_overrides then
      local data = encounter_tuning_overrides[in_edge]
      local override_tests = data and data.can_start
      if override_tests then
         tests = override_tests
      end
   end

   if tests then
      if not self:_any_test_set_passes(ctx, tests) then
         self._log:info('check failed! %s node cannot start', in_edge or self._sv._info.type)
         return false
      end
   end
   self._log:info('all passed!')
   return true
end

function Node:get_ctx()
   assert(self._sv.ctx)
   return self._sv.ctx
end

function Node:get_info()
   return self._sv._info
end

-- ACE: deep copy the cached json so that things like random i18n string selections from tables don't override the cache
function Node:load_json()
   if self._sv.json_path then
      -- true for cache, false for don't report error if json doesn't exist.
      -- If the json file doesn't exist, the NodeList's post activate will reap us
      self._sv._info = radiant.deep_copy(radiant.resources.load_json(self._sv.json_path, true, false))
   end
end

function Node:is_json_deleted()
   return self._sv.json_path and not self._sv._info
end

return Node
