local Entity = _radiant.om.Entity
local DropOffBuildingMaterial = radiant.class()
DropOffBuildingMaterial.name = 'drop off building material'
DropOffBuildingMaterial.does = 'stonehearth_ace:drop_off_building_material'
DropOffBuildingMaterial.args = {
   building = Entity,
   material = 'string',
}
DropOffBuildingMaterial.priority = 1

function DropOffBuildingMaterial:run(ai, entity, args)
   local building_comp = args.building:get_component('stonehearth:build2:building')
   if not building_comp then
      ai:abort('no building!')
   end

   -- verify that the carried item exists and has a material needed by the building
   local item = radiant.entities.get_carrying(entity)
   if not item or not building_comp:try_bank_resource(item, args.material) then
      ai:abort('no carried resource or can no longer be banked')
   end

   local container = building_comp:get_resource_delivery_entity()
   radiant.entities.turn_to_face(entity, container)
   local container_location = radiant.entities.get_world_grid_location(container)
   ai:execute('stonehearth:run_putdown_effect', { location = container_location })
   
   radiant.entities.destroy_entity(item)
end

return DropOffBuildingMaterial
