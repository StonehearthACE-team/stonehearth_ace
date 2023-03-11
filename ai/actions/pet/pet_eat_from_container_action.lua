local PetEatFromContainerAction = radiant.class()

PetEatFromContainerAction.name = 'pet eat from container'
PetEatFromContainerAction.does = 'stonehearth:pet_eat_directly'
PetEatFromContainerAction.args = {}
PetEatFromContainerAction.priority = 0.5

function PetEatFromContainerAction:start_thinking(ai, entity, args)
   local diet_data = radiant.entities.get_entity_data(entity, 'stonehearth:diet')
   if diet_data then
      if diet_data.food_material then
         ai:set_think_output( {material = diet_data.food_material..' food_container'} )
      end
   else
      ai:set_think_output( {material = 'food_container'} )
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEatFromContainerAction)
   :execute('stonehearth:goto_item_made_of', { material = ai.PREV.material, owner = ai.ENTITY:get_player_id() })
      -- reserve item after we get there. let humans reserve first
   :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
   :execute('stonehearth:pet_eat_from_container_adjacent', { container = ai.BACK(2).item })
