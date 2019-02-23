--[[
   tracks and updates data for all tier 3 towns outside of saved games, whenever those towns are saved
   also importantly maintains an id that's set when a game is created to prevent duplication
]]

local rng = _radiant.math.get_default_rng()

local PersistenceService = class()

function PersistenceService:initialize()
   self:_load_all_persistence_data()
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
      for _, town in pairs(data) do
         town.save_id = save_id
         table.insert(self._towns, town)
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

-- this only needs to be called immediately before saving the game
-- get all persistence data for towns that are tier 3
function PersistenceService:save_town_data()
   local game_id = self:_get_game_id()
   if not game_id then
      return
   end

   local data = stonehearth.town:get_persistence_data()
   if data and next(data) then
      radiant.mods.write_object('persistence/' .. game_id, data)
   end
end

function PersistenceService:_get_game_id()
   return stonehearth.game_creation:get_game_id()
end

return PersistenceService