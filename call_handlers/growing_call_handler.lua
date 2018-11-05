--[[
   call handlers for getting information to the UI about growing/evolve preferences (e.g., water-related)
]]

local GrowingCallHandler = class()

function GrowingCallHandler:get_growth_preferences_command(session, response, uri)
   local growing_data = radiant.entities.get_component_data(uri, 'stonehearth:growing')
   local best_affinity, next_affinity = stonehearth.town:get_best_water_level_from_climate(growing_data.preferred_climate)
   local aquatic_data = radiant.entities.get_component_data(uri, 'stonehearth_ace:aquatic_object') or {}

   response:resolve({
      preferred_climate = growing_data.preferred_climate,
      flood_period_multiplier = growing_data.flood_period_multiplier or 2,
      water_affinity = {
         best_affinity = best_affinity,
         next_affinity = next_affinity
      },
      require_flooding_to_grow = aquatic_data.require_water_to_grow
   })
end

return GrowingCallHandler