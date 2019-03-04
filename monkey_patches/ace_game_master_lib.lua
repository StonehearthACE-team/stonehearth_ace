local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local ace_game_master_lib = {}

ace_game_master_lib._ace_old_create_citizens = game_master_lib.create_citizens
function ace_game_master_lib.create_citizens(population, info, origin, ctx)
   local citizens = ace_game_master_lib._ace_old_create_citizens(population, info, origin, ctx)

   if info.statistics then
      for i, citizen in ipairs(citizens) do
         if info.statistics.is_notable then
            citizen:add_component('stonehearth:unit_info'):set_notability(true)
         end
         -- any other statistics-based settings?
      end
   end

   return citizens
end

return ace_game_master_lib