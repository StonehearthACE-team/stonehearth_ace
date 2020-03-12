local PetEatPetFoodOnGround = radiant.class()

PetEatPetFoodOnGround.name = 'pet eat pet food from ground'
PetEatPetFoodOnGround.does = 'stonehearth:pet_eat_directly'
PetEatPetFoodOnGround.args = {}
PetEatPetFoodOnGround.priority = 0.8

function PetEatPetFoodOnGround:start_thinking(ai, entity, args)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
   if diet_data then
      if diet_data.food_material then
         ai:set_think_output( {material = diet_data.food_material..' pet_food'} )
      end
   else
      ai:set_think_output( {material = 'pet_food'} )
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatPetFoodOnGround)
   :execute('stonehearth:goto_item_made_of', { material = ai.PREV.material, owner = ai.ENTITY:get_player_id() })
   -- reserve item after we get there. let humans reserve first
   :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
   :execute('stonehearth:eat_item', { food = ai.PREV.entity })
