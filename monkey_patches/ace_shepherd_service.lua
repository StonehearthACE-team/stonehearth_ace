local ShepherdService = require 'stonehearth.services.server.shepherd.shepherd_service'
AceShepherdService = class()

AceShepherdService._ace_old_create_new_pasture = ShepherdService.create_new_pasture
function AceShepherdService:create_new_pasture(session, location, size)
	local entity = self:_ace_old_create_new_pasture(session, location, size)
	local pasture_component = entity:get_component('stonehearth:shepherd_pasture')
	pasture_component:post_creation_setup()

   radiant.entities.set_entity_movement_modifier(entity, entity:get_component('region_collision_shape'):get_region():get())

	return entity
end

return AceShepherdService
