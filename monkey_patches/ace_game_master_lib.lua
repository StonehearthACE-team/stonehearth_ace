local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local ace_game_master_lib = {}

ace_game_master_lib._ace_old_create_citizens = game_master_lib.create_citizens
function ace_game_master_lib.create_citizens(population, info, origin, ctx)
   local citizens = ace_game_master_lib._ace_old_create_citizens(population, info, origin, ctx)

   for i, citizen in ipairs(citizens) do
      if info.combat_leash_range then
         stonehearth.combat:set_leash(citizen, origin, (info.combat_leash_range + stonehearth.constants.combat.ADDITIVE_COMBAT_LEASH_BONUS))
      end
   end

   local tuning
   if info.tuning then
      tuning = radiant.resources.load_json(info.tuning)
   end

   local info_statistics = info and info.statistics
   local tuning_statistics = tuning and tuning.statistics

   if info_statistics or tuning_statistics then
      -- tuning can override info for any individual aspect
      local statistics = radiant.shallow_copy(info_statistics or {})
      radiant.util.merge_into_table(statistics, tuning_statistics or {})

      for i, citizen in ipairs(citizens) do
         if statistics.is_notable then
            radiant.entities.set_property_value(citizen, 'notable', true)
         end
         -- any other statistics-based settings?
         if statistics.specifier then
            radiant.entities.set_property_value(citizen, 'stats_specifier', statistics.specifier)
         end
      end
   end

   return citizens
end

return ace_game_master_lib