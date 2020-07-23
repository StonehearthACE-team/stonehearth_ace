--[[
   tracks and updates data for all tier 3 towns outside of saved games, whenever those towns are saved
   also importantly maintains an id that's set when a game is created to prevent duplication
]]

local rng = _radiant.math.get_default_rng()

local PersistenceService = class()

local PERSISTENCE_SAVE_TIME = '07:30am'

function PersistenceService:initialize()
   self:_load_all_persistence_data()

   self._save_alarm = stonehearth.calendar:set_alarm(PERSISTENCE_SAVE_TIME, function()
      self:save_town_data()
   end)
end

function PersistenceService:destroy()
   if self._save_alarm then
      self._save_alarm:destroy()
      self._save_alarm = nil
   end
end

-- ignore any persistence data for this save
-- we don't want old data from this save being used for generating content for current activity in it
function PersistenceService:_load_all_persistence_data()
   local game_id = self:_get_game_id()
   
   self._all_persistence_data = {}
   local unique_saves = radiant.mods.enum_objects('persistence')
   for _, save_id in ipairs(unique_saves) do
      if save_id ~= game_id then
         self._all_persistence_data[save_id] = radiant.mods.read_object('persistence/' .. save_id)
      end
   end

   self._towns = {}
   for save_id, data in pairs(self._all_persistence_data) do
      local towns = data.towns or data
      for player_id, town in pairs(data) do
         town.save_id = save_id
         table.insert(self._towns, town)
      end

      -- TODO: also track other information about the save in the persistence data, like biome, age, etc.
      if data.biome then

      end
   end

   self._all_crafters = {}
   self._crafters_by_job = {}
   for _, town in ipairs(self._towns) do
      if town.crafters then
         for job_uri, crafters in pairs(town.crafters) do
            local crafter_type = self._crafters_by_job[job_uri]
            if not crafter_type then
               crafter_type = {}
               self._crafters_by_job[job_uri] = crafter_type
            end
            for _, crafter in ipairs(crafters) do
               crafter.job_uri = job_uri
               crafter.town = town   -- allow us to easily reference this crafter's town
               table.insert(crafter_type, crafter)
               table.insert(self._all_crafters, crafter)
            end
         end
      end
   end
end

function PersistenceService:get_all_towns()
   return self._towns
end

function PersistenceService:get_random_town()
   if #self._towns > 0 then
      return self._towns[rng:get_int(1, #self._towns)]
   end
end

function PersistenceService:get_save_by_id(save_id)
   return self._all_persistence_data[save_id]
end

function PersistenceService:get_all_crafters(job_uri)
   if job_uri then 
      return self._crafters_by_job[job_uri]
   else
      return self._all_crafters
   end
end

function PersistenceService:get_random_crafter(job_uri)
   local crafters = self:get_all_crafters(job_uri)

   if crafters and #crafters > 0 then
      return crafters[rng:get_int(1, #crafters)]
   end
end

-- this only needs to be called immediately before saving the game
-- get all persistence data for towns that are tier 3
function PersistenceService:save_town_data()
   local game_id = self:_get_game_id()
   if not game_id or game_id == '' then
      return
   end

   local town_data = stonehearth.town:get_persistence_data()
   if town_data and next(town_data) then
      -- TODO: add biome data, age, any other data we want to track about each save
      local data = {
         towns = town_data,
      }
      radiant.mods.write_object('persistence/' .. game_id, data)
   end
end

function PersistenceService:_get_game_id()
   return stonehearth.game_creation:get_game_id()
end

return PersistenceService