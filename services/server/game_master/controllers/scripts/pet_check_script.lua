local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local PetCheck = class()

function PetCheck:start(ctx, info)
   local town = stonehearth.town:get_town(ctx.player_id)      
   local town_pets ={}                          
      
   if town then
      town_pets = town:get_pets()
      if town_pets ~= {} then
         for _, pet in pairs(town_pets) do
            local pet_uri = pet:get_uri()
            if pet_uri == info.required_pet then
               if info.register_to_ctx and info.ctx_registration_path then
                  game_master_lib.register_entities(ctx, info.ctx_registration_path, { pet = pet })
               end
               return true
            end
         end
         return false
      else
         return false
      end
   end

   return false
end

return PetCheck