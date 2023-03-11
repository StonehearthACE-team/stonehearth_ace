local Entity = _radiant.om.Entity

local PetEatFromFoodDishAdjacent = radiant.class()
PetEatFromFoodDishAdjacent.name = 'eat item'
PetEatFromFoodDishAdjacent.does = 'stonehearth:pet_eat_from_container_adjacent'
PetEatFromFoodDishAdjacent.args = {
   container = Entity,
   storage = {
      type = Entity,
      default = stonehearth.ai.NIL,
   }
}
PetEatFromFoodDishAdjacent.priority = 0

function PetEatFromFoodDishAdjacent:run(ai, entity, args)
   local container = args.container
   local container_data = radiant.entities.get_entity_data(container, 'stonehearth:food_container') or
         radiant.entities.get_entity_data(container, 'stonehearth_ace:pet_food_container')
   if not container_data then
      ai:abort(string.format("%s has no stonehearth:food_container or stonehearth_ace:pet_food_container entity data", tostring(container)))
      return
   end

   -- if a storage entity is specified, face that instead
   local face_entity = args.storage or container
   radiant.entities.turn_to_face(entity, face_entity)
   ai:execute('stonehearth:run_effect', { effect = container_data.effect })

   -- consume the stack after the effect finishes.  this might end up destroying the container
   -- so unprotect it first; also release the lease on it so others can use it
   -- go ahead and get its quality now before we do that
   local quality_component = container:get_component("stonehearth:item_quality")
   local container_quality = (quality_component and quality_component:get_quality()) or 0
   ai:unprotect_argument(container)
   stonehearth.ai:release_ai_lease(container, entity)

   local stacks_per_serving = container_data.stacks_per_serving or 1
   if not radiant.entities.consume_stack(container, stacks_per_serving) then
      ai:abort('Cannot eat: Food container is empty.')
   end

   local food = radiant.entities.create_entity(container_data.food, { owner = entity })

   --food servings inherit their quality from their parent
   if container_quality > stonehearth.constants.item_quality.NORMAL then
      food:add_component('stonehearth:item_quality'):initialize_quality(container_quality, nil, nil, {override_allow_variable_quality=true})
   end

   ai:execute('stonehearth:eat_item', { food = food })
end

return PetEatFromFoodDishAdjacent
