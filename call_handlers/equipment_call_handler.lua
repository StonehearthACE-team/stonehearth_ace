local validator = radiant.validator
local EquipmentCallHandler = class()

function EquipmentCallHandler:shield_pavise_toggle(session, response, entity, toggle)
   validator.expect_argument_types({'Entity', 'string'}, entity, toggle)
   validator.expect.matching_player_id(session.player_id, entity)

   local equipment = entity:get_component('stonehearth:equipment')
   if not equipment then
      return false
   end

   if toggle == 'deploy' and stonehearth.combat:is_in_combat(entity) then
      radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:shield_pavise:deployed')
   end

   if toggle == 'undeploy' then
      radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:shield_pavise:deployed')
   end
end

return EquipmentCallHandler
