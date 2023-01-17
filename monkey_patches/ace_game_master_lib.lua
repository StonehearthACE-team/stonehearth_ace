local constants = require 'stonehearth.constants'
local DEFAULT_QUEST_STORAGE_URI = constants.game_master.quests.DEFAULT_QUEST_STORAGE_CONTAINER_URI

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

function ace_game_master_lib.create_quest_storage(player_id, uri, item_requirements, bulletin, location)
   local town = stonehearth.town:get_town(player_id)
   if not town then
      return
   end

   local drop_origin = town:get_landing_location()
   if not drop_origin and not location then
      return
   end

   uri = uri or town:get_default_quest_storage_uri() or DEFAULT_QUEST_STORAGE_URI
   local quest_storage = radiant.entities.create_entity(uri, { owner = player_id })
   if not location then
      local valid
      location, valid = radiant.terrain.find_placement_point(drop_origin, 4, 7, quest_storage)
      if not valid then
         radiant.entities.destroy_entity(quest_storage)
         return
      end
   end

   -- create a quest storage near the town banner for these items
   local qs_comp = quest_storage:add_component('stonehearth_ace:quest_storage')
   qs_comp:set_requirements(item_requirements)
   qs_comp:set_bulletin(bulletin)
   radiant.terrain.place_entity_at_exact_location(quest_storage, location, {force_iconic = false})
   radiant.effects.run_effect(quest_storage, 'stonehearth:effects:gib_effect')

   return quest_storage
end

return ace_game_master_lib