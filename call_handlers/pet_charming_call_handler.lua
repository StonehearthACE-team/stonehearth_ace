local validator = radiant.validator

local PetCharmingCallHandler = class()

function PetCharmingCallHandler:allow_pet_charming_for_entity(session, response, entity, enable)
   validator.expect_argument_types({'Entity'}, entity)
   validator.expect.matching_player_id(session.player_id, entity)
   
   local commands = entity:add_component('stonehearth:commands')

   if enable then
      entity:add_component('stonehearth:buffs'):remove_buff('stonehearth_ace:buffs:avoid_pet_charming', true)
      commands:remove_command('stonehearth_ace:commands:allow_pet_charming')
      commands:add_command('stonehearth_ace:commands:avoid_pet_charming')
   else
      entity:add_component('stonehearth:buffs'):add_buff('stonehearth_ace:buffs:avoid_pet_charming')
      commands:remove_command('stonehearth_ace:commands:avoid_pet_charming')
      commands:add_command('stonehearth_ace:commands:allow_pet_charming')
   end
end

return PetCharmingCallHandler