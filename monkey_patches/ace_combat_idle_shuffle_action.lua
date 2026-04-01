local AceCombatIdleShuffle = radiant.class()

function AceCombatIdleShuffle:_no_shuffle(entity)
   local entity_data = radiant.entities.get_entity_data(entity, 'stonehearth:combat')

   if entity_data and entity_data.no_shuffle ~= nil then
      return entity_data.no_shuffle
   end

   local attributes_comp = entity:get_component('stonehearth:attributes')
   local speed = attributes_comp and attributes_comp:get_attribute('speed')
   local weapon = stonehearth.combat:get_main_weapon(entity)
   local weapon_data = weapon and radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
   local ranged = weapon_data and weapon_data['base_ranged_damage']

   if speed and speed < 10 then
      return true
   end

   if ranged and ranged > 0 then
      return true
   end

   return false
end

return AceCombatIdleShuffle
