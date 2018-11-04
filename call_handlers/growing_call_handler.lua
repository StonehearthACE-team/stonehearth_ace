--[[
   call handlers for getting information to the UI about growing/evolve preferences (e.g., water-related)
]]

local GrowingCallHandler = class()

function GrowingCallHandler:get_growth_preferences_command(session, response, uri)
   local growing_data = radiant.entities.get_component_data(uri, 'stonehearth:growing')
   local best_affinity, next_affinity = stonehearth.town:get_best_water_level_from_climate(growing_data.preferred_climate)
   
   response:resolve({
      water_affinity = {
         best_affinity = best_affinity,
         next_affinity = next_affinity
      }
   })
end

return GrowingCallHandler