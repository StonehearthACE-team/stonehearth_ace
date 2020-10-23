local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local util = require 'stonehearth_ace.lib.util'

local TrappingService = require 'stonehearth.services.server.trapping.trapping_service'
AceTrappingService = class()

-- AceTrappingService._ace_old_destroy = TrappingService.__user_destroy
-- function AceTrappingService:destroy()
--    self:_destroy_all_listeners()
--    self:_ace_old_destroy()
-- end

-- function AceTrappingService:_destroy_all_listeners()
--    if self._fish_traps then
--       for _, trap_data in pairs(self._fish_traps) do
--          self:_destroy_predestroy_listener(trap_data)
--       end
--    end
-- end

-- function AceTrappingService:_destroy_predestroy_listener(trap_data)
--    if trap_data.water_predestroy_listener then
--       trap_data.water_predestroy_listener:destroy()
--       trap_data.water_predestroy_listener = nil
--    end
-- end

function AceTrappingService:_setup_fish_trapping()
   -- load up trapping data from json
   -- set up a season listener to inform the trapping service that the loot cache is no longer valid
   self._all_fish_trap_loot = radiant.resources.load_json('stonehearth_ace:trapper:fish_trap:loot_table')
   self._season_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
      self._fish_trap_season_cached = false
   end)
end

function AceTrappingService:get_fish_trap_capture_loot_table()
   self:_ensure_fish_trap_loot_tables()

   return self._fish_trap_capture_biome_loot_table
end

function AceTrappingService:get_fish_trap_harvest_loot_table()
   self:_ensure_fish_trap_loot_tables()

   return self._fish_trap_harvest_loot_table
end

function AceTrappingService:_ensure_fish_trap_loot_tables()
   if not self._fish_trap_biome_cached then
      self:_cache_fish_trap_biome_loot_tables()
   end

   if not self._fish_trap_season_cached then
      self:_cache_fish_trap_season_loot_tables()
   end
end

function AceTrappingService:_cache_fish_trap_biome_loot_tables()
   self._fish_trap_biome_cached = true
   self._fish_trap_season_cached = false

   local biome_uri = stonehearth.world_generation:get_biome_alias()

   local all_capture_loot = self._all_fish_trap_loot.capture_loot
   local biome_capture_loot = all_capture_loot.biomes and all_capture_loot.biomes[biome_uri]
   self._biome_capture_seasons_loot = biome_capture_loot and biome_capture_loot.seasons or {}

   local all_harvest_loot = self._all_fish_trap_loot.harvest_loot
   local biome_harvest_loot = all_harvest_loot.biomes and all_harvest_loot.biomes[biome_uri]
   self._biome_harvest_seasons_loot = biome_harvest_loot and biome_harvest_loot.seasons or {}
   
   self._fish_trap_capture_biome_loot_table = self:_merge_loot_tables(all_capture_loot.default, biome_capture_loot and biome_capture_loot.default)
   self._fish_trap_harvest_biome_loot_table = self:_merge_loot_tables(all_harvest_loot.default, biome_harvest_loot and biome_harvest_loot.default)
end

function AceTrappingService:_cache_fish_trap_season_loot_tables()
   self._fish_trap_season_cached = true

   local season_id = stonehearth.seasons:get_current_season().id

   local all_capture_loot = self._all_fish_trap_loot.capture_loot
   local season_capture_loot = all_capture_loot.seasons and all_capture_loot.seasons[season_id]
   local biome_season_capture_loot = self._biome_capture_seasons_loot[season_id]
   local biome_capture_loot = radiant.deep_copy(self._fish_trap_capture_biome_loot_table)

   local all_harvest_loot = self._all_fish_trap_loot.harvest_loot
   local season_harvest_loot = all_harvest_loot.seasons and all_harvest_loot.seasons[season_id]
   local biome_season_harvest_loot = self._biome_harvest_seasons_loot[season_id]
   local biome_harvest_loot = radiant.deep_copy(self._fish_trap_harvest_biome_loot_table)
   
   -- deep copy the biome loot table so we don't have to recreate it when the season changes
   self._fish_trap_capture_loot_table = self:_merge_loot_tables(self:_merge_loot_tables(biome_capture_loot, season_capture_loot), biome_season_capture_loot)
   self._fish_trap_harvest_loot_table = self:_merge_loot_tables(self:_merge_loot_tables(biome_harvest_loot, season_harvest_loot), biome_season_harvest_loot)
end

function AceTrappingService:_merge_loot_tables(t1, t2)
   -- if they have values, assume they're tables
   if t1 and t2 then
      return util.deep_merge(t1, t2)
   else
      return t1 or t2
   end
end

-- register fish traps and index them by the water entity they fish from
-- making it easy for a trap to check what other traps it might be contesting
function AceTrappingService:register_fish_trap(trap, water_entity)
   if not self._fish_traps then
      self._fish_traps = {}
   end

   local water_id = water_entity:get_id()
   local trap_data = self._fish_traps[water_id]
   if not trap_data then
      trap_data = {
         traps = {},
         water_entity = water_entity,
         -- water_predestroy_listener = radiant.events.listen(water_entity, 'radiant:entity:pre_destroy', function()
         --       self:_remove_water_entity(water_id)
         --    end)
      }

      self._fish_traps[water_id] = trap_data
   end

   local trap_id = trap:get_id()
   trap_data.traps[trap_id] = trap
   self:_queue_inform_traps_of_potential_conflict(water_id, trap_id)
end

function AceTrappingService:unregister_fish_trap(trap_id, water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      trap_data.traps[trap_id] = nil
      if next(trap_data.traps) then
         self:_queue_inform_traps_of_potential_conflict(water_id)
      else
         self:_remove_water_entity(water_id)
      end
   end
end

function AceTrappingService:_remove_water_entity(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      -- self:_destroy_predestroy_listener(trap_data)
      -- for _, trap in pairs(trap_data.traps) do
      --    local trap_component = trap:get_component('stonehearth_ace:fish_trap')
      --    if trap_component then
      --       trap_component:recheck_water_entity()
      --    end
      -- end
      self._fish_traps[water_id] = nil
   end
end

function AceTrappingService:_queue_inform_traps_of_potential_conflict(water_id, except_trap_id)
   if not self._queued_inform then
      self._queued_inform = {}
   end

   local queued = self._queued_inform[water_id]
   if queued then
      if queued.except_trap_id ~= except_trap_id then
         queued.except_trap_id = nil
      end
   else
      self._queued_inform[water_id] = {except_trap_id = except_trap_id}
   end

   if not self._on_next_game_loop then
      self._on_next_game_loop = radiant.on_game_loop_once('inform fish traps of potential conflicts', function()
            local queued = self._queued_inform
            self._queued_inform = {}
            self._on_next_game_loop = nil

            for water_id, detail in pairs(queued) do
               local trap_data = self._fish_traps[water_id]
               if trap_data then
                  self:_inform_traps_of_potential_conflict(trap_data.traps, detail.except_trap_id)
               end
            end
         end)
   end
end

function AceTrappingService:_inform_traps_of_potential_conflict(traps, except_id)
   for trap_id, trap in pairs(traps) do
      if trap_id ~= except_id then
         local trap_component = trap:get_component('stonehearth_ace:fish_trap')
         if trap_component then
            trap_component:recheck_effective_water_volume()
         end
      end
   end
end

function AceTrappingService:get_fish_traps_in_water(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   if trap_data then
      return radiant.shallow_copy(trap_data.traps)
   end
end

function AceTrappingService:get_num_fish_traps_in_water(water_id)
   local trap_data = self._fish_traps and self._fish_traps[water_id]
   return trap_data and radiant.size(trap_data.traps) or 0
end

function AceTrappingService:get_all_trappable_animals_command(session, response)
   -- no longer player based, it's biome-based (just get it from the component data of the trapping zone entity)
   -- base game initializes self._trappable_animals as an empty table, so check if it's not empty
   local trappable_animals = self._trappable_animals
   if not trappable_animals or not next(trappable_animals) then
      trappable_animals = radiant.entities.get_component_data('stonehearth:trapper:trapping_grounds', 'stonehearth:trapping_grounds').trappable_animals
      self._trappable_animals = trappable_animals
   end
   response:resolve({ animals = trappable_animals})
end

return AceTrappingService
