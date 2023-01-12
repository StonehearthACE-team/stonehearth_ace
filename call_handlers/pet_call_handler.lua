local validator = radiant.validator

local PetCallHandler = class()

function PetCallHandler:set_pet_owner(session, response, pet, owner)
   validator.expect_argument_types({'Entity', 'Entity'}, pet, owner)

   if session.player_id ~= pet:get_player_id() or session.player_id ~= owner:get_player_id() then
      return false
   else
      radiant.entities.add_pet(owner, pet)
   end
end

return PetCallHandler
