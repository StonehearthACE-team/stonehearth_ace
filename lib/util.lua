local Point3 = _radiant.csg.Point3
local _is_table = radiant.util.is_table

local util = {}

-- Taken from https://web.archive.org/web/20131225070434/http://snippets.luacode.org/snippets/Deep_Comparison_of_Two_Values_3
function util.deep_compare(t1, t2, ignore_mt)
   local ty1 = type(t1)
   local ty2 = type(t2)
   if ty1 ~= ty2 then return false end
   -- non-table types can be directly compared
   if ty1 ~= 'table' then return t1 == t2 end
   -- as well as tables which have the metamethod __eq
   if not ignore_mt then
      local mt = getmetatable(t1)
      if mt and mt.__eq then return t1 == t2 end
   end
   for k1, v1 in pairs(t1) do
      local v2 = t2[k1]
      if v2 == nil or not util.deep_compare(v1, v2, ignore_mt) then return false end
   end
   for k2, v2 in pairs(t2) do
      local v1 = t1[k2]
      if v1 == nil or not util.deep_compare(v1, v2, ignore_mt) then return false end
   end
   return true
end

function util.itable_append(t1, t2)
   for _, v in pairs(t2) do
      t1[#t1+1] = v
   end
   return t1
end

-- used for seeing if two sequences share all the same values
function util.sequence_equals(t1, t2)
   if #t1 ~= #t2 then
      return false
   end

   for i = 1, #t1 do
      if t1[i] ~= t2[i] then
         return false
      end
   end

   return true
end

function util.sum_where_all_keys_present(key_maps, values, keys)
   if type(keys) == 'string' then
      keys = radiant.util.split_string(keys, ' ')
   end

   local total_value = 0

   for match_key, key_map in pairs(key_maps) do
      local match = true
      for _, key in ipairs(keys) do
         if not key_map[key] then
            match = false
            break
         end
      end
      if match then
         total_value = total_value + values[match_key]
      end
   end

   return total_value
end

--[[
   expects rules to be an array of rules to evaluated against the given property value:
   [
      {
         "comparator": ">="
         "value": 5
      }
   ]
]]

function util._eval_property_rule(value, comparator, rule_value)
   if comparator == 'none' and (value == nil or (_is_table(value) and #value == 0)) then
      return true
   elseif comparator == 'any' and value ~= nil and (not _is_table(value) or #value > 0) then
      return true
   end

   -- if the value is an array, then check if any of the elements satisfy the rule
   if _is_table(value) then
      for _, value_i in ipairs(value) do
         if util._eval_property_rule(value_i, comparator, rule_value) then
            return true
         end
      end
   else
      if comparator == '==' and value and value == rule_value then
         return true
      elseif comparator == '==|none' and (value == nil or value == rule_value) then
         return true
      elseif comparator == '!=' and value and value ~= rule_value then
         return true
      elseif comparator == '!=|none' and (value == nil or value ~= rule_value) then
         return true
      elseif comparator == '<' and value and value < rule_value then
         return true
      elseif comparator == '<=' and value and value <= rule_value then
         return true
      elseif comparator == '>' and value and value > rule_value then
         return true
      elseif comparator == '>=' and value and value >= rule_value then
         return true
      end
   end

   return false
end

-- returns true if *any* rule evaluates to true (OR)
function util.eval_property_or(value, rules)
   for _, rule in ipairs(rules) do
      if util._eval_property_rule(value, rule.comparator, rule.value) then
         return true
      end
   end

   return false
end

-- returns true if *all* rules evaluates to true (AND)
function util.eval_property_and(value, rules)
   for _, rule in ipairs(rules) do
      if not util._eval_property_rule(value, rule.comparator, rule.value) then
         return false
      end
   end

   return true
end

function util.get_current_conditions_loot_table_filter_args(looter)
   -- get biome, season, weather, and hour of day
   local biome = stonehearth.world_generation:get_biome_alias()
   local season = stonehearth.seasons:get_current_season()
   season = season and season.id
   local weather = stonehearth.weather:get_current_weather()
   weather = weather and weather:get_uri()
   local hour = stonehearth.calendar:get_time_and_date().hour

   local args = {
      biome = { {
         comparator = '==|none',
         value = biome,
      } },
      season = { {
         comparator = '==|none',
         value = season,
      } },
      weather = { {
         comparator = '==|none',
         value = weather,
      } },
      min_hour = {
         {
            comparator = 'none'
         },
         {
            comparator = '>=',
            value = hour,
         },
      },
      max_hour = {
         {
            comparator = 'none'
         },
         {
            comparator = '<=',
            value = hour,
         },
      },
   }

   if looter and looter:is_valid() then
      -- if a looter is specified, add conditions related to them and their town
      local player_id = radiant.entities.get_player_id(looter)
      local player_jobs = player_id and stonehearth.job:get_jobs_controller(player_id)
      if player_jobs then
         local highest_lvls = {}
         for uri, job_info in pairs(player_jobs:get_jobs()) do
            local lvl = job_info:get_highest_level()
            if lvl > 0 then
               highest_lvls[uri] = lvl
            end
         end

         if next(highest_lvls) then
            for uri, lvl in pairs(highest_lvls) do
               args['highest_level_' .. uri] = {
                  {
                     comparator = 'none'
                  },
                  {
                     comparator = '>=',
                     value = lvl,
                  },
               }
            end
         end
      end

      local job = looter:get_component('stonehearth:job')
      if job then
         local job_uri = job:get_job_uri()
         local job_level = job:get_current_job_level()
         args.current_job = { {
            comparator = '==|none',
            value = job_uri,
         } }
         args.current_job_level = {
            {
               comparator = 'none'
            },
            {
               comparator = '>=',
               value = job_uri,
            },
         }
      end
   end

   return args
end

return util
