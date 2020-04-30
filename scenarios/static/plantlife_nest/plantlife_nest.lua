local PlantlifeNest = class()

function PlantlifeNest:__init()
end

function PlantlifeNest:initialize(properties, context, services)
   local data = properties.data
   local num_entities = services.rng:get_int(data.quantity.min, data.quantity.max)
   services:place_entity_cluster(data.entity_type, num_entities, data.entity_footprint_length, true, { force_iconic = false })
end

return PlantlifeNest
