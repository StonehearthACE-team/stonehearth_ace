local Entity = _radiant.om.Entity
local RegisterBuildingMaterialDropOff = radiant.class()

RegisterBuildingMaterialDropOff.name = 'register a construction material to be banked at a building'
RegisterBuildingMaterialDropOff.does = 'stonehearth_ace:register_building_material_drop_off'
RegisterBuildingMaterialDropOff.args = {
   building = Entity,
   material = 'string',
   item = Entity,
}
RegisterBuildingMaterialDropOff.priority = 0.0

function RegisterBuildingMaterialDropOff:start_thinking(ai, entity, args)
   local building = args.building:get_component('stonehearth:build2:building')
   local resource_needed = building and building:get_remaining_resource_cost(entity)
   if resource_needed and resource_needed[args.material] then
      ai:set_think_output({})
   end
end

function RegisterBuildingMaterialDropOff:start(ai, entity, args)
   local building = args.building:get_component('stonehearth:build2:building')
   local resource_needed = building and building:get_remaining_resource_cost(entity)
   if resource_needed and resource_needed[args.material] then
      building:register_material_to_be_banked(entity, args.material, args.item)
   else
      ai:abort('no more building or resource needed')
   end
end

function RegisterBuildingMaterialDropOff:stop(ai, entity, args)
   local building = args.building:get_component('stonehearth:build2:building')
   if building then
      building:unregister_material_to_be_banked(entity:get_id(), args.material)
   end
end

return RegisterBuildingMaterialDropOff
