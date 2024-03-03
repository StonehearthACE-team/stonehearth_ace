local Entity = _radiant.om.Entity

local GetDrinkFromContainerAdjacent = class()
GetDrinkFromContainerAdjacent.name = 'get drink from container adjacent'
GetDrinkFromContainerAdjacent.does = 'stonehearth_ace:get_drink_from_container_adjacent'
GetDrinkFromContainerAdjacent.args = {
   container = Entity,
   storage = {
      type = Entity,
      default = stonehearth.ai.NIL,
   }
}
GetDrinkFromContainerAdjacent.priority = 0

function GetDrinkFromContainerAdjacent:run(ai, entity, args)
   local container = args.container

   if not container:is_valid() then
      ai:abort(string.format("%s is no longer a valid entity (maybe should've protected it!)", tostring(container)))
      return
   end

   local container_data = radiant.entities.get_entity_data(container, 'stonehearth_ace:drink_container')
   if not container_data then
      ai:abort(string.format("%s has no stonehearth_ace:drink_container entity data", tostring(container)))
      return
   end

   local quality_component = container:get_component("stonehearth:item_quality")
   local container_quality = (quality_component and quality_component:get_quality()) or 0

   if container_data.container_effect then
      radiant.effects.run_effect(container, container_data.container_effect)
   end

   -- if a storage entity is specified, face that instead
   local face_entity = args.storage or container
   radiant.entities.turn_to_face(entity, face_entity)
   ai:execute('stonehearth:run_effect', { effect = container_data.effect })

   -- go ahead and release it for others while we sit and drink
   stonehearth.ai:release_ai_lease(container, entity)

   -- if specified, create a subcontainer entity to drop on the ground and drink from that instead
   -- while loop allows for nesting dolls, I guess (primary functionality is water buckets from wells)
   while container_data.subcontainer do
      local stacks_per_serving = container_data.stacks_per_serving or 1
      if stacks_per_serving > 0 then
         ai:unprotect_argument(container)
         if not radiant.entities.consume_stack(container, stacks_per_serving) then
            ai:abort('Cannot drink: Drink container is empty.')
            return
         end
      end

      local subcontainer = radiant.entities.create_entity(container_data.subcontainer, { owner = entity })
      if container_quality > stonehearth.constants.item_quality.NORMAL then
         subcontainer:add_component('stonehearth:item_quality'):initialize_quality(container_quality, nil, nil, {override_allow_variable_quality=true})
      end

      stonehearth.ai:pickup_item(ai, entity, subcontainer)
      ai:execute('stonehearth:drop_carrying_now')
      container = subcontainer
      container_data = radiant.entities.get_entity_data(container, 'stonehearth_ace:drink_container')
      radiant.entities.turn_to_face(entity, container)

      -- no effects for subcontainers; do we really need them?
   end

   local model_variant
   if container_data.dynamic_serving_model then
      model_variant = container:add_component('render_info'):get_model_variant()
   end

   local stacks_per_serving = container_data.stacks_per_serving or 1
   if stacks_per_serving > 0 then
      ai:unprotect_argument(container)
      if not radiant.entities.consume_stack(container, stacks_per_serving) then
         ai:abort('Cannot drink: Drink container is empty.')
         return
      end
   end

   local drink = radiant.entities.create_entity(container_data.drink, { owner = entity })

   if container_quality > stonehearth.constants.item_quality.NORMAL then
      drink:add_component('stonehearth:item_quality'):initialize_quality(container_quality, nil, nil, {override_allow_variable_quality=true})
   end

   if container_data.serving_model then
      drink:add_component('stonehearth_ace:entity_modification'):set_model_variant(container_data.serving_model)
   end

   if model_variant then
      drink:add_component('stonehearth_ace:entity_modification'):set_model_variant(model_variant)
   end

   stonehearth.ai:pickup_item(ai, entity, drink)
end

return GetDrinkFromContainerAdjacent
