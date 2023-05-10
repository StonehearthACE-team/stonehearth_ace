local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'
local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('landmark_renderer')

local AceLandmarkRenderer = class()

function AceLandmarkRenderer:_regenerate_visualization()
   if self._visualization_node then
      self._visualization_node:destroy()
      self._visualization_node = nil
   end
   
   local landmark_spec = self._landmark_spec
   if not landmark_spec then
      return
   end

   local landmark_block_types = self._landmark_block_types
   if not landmark_block_types then
      landmark_block_types = radiant.resources.load_json(landmark_spec.landmark_block_types, true, false)
      self._landmark_block_types = landmark_block_types
   end

   -- This doesn't interact correctly with terrain bounds, but that's probably acceptable for a preview.
   local region = landmark_lib.get_generated_landmark_region(nil, landmark_spec)
   region = landmark_lib.remove_tagged_blocks(region, landmark_block_types, {[0] = true})

   local color = { x = 32, y = 96, z = 32 }
   if stonehearth.presence_client:is_multiplayer() then
      local player_id = radiant.entities.get_player_id(self._entity)
      color = stonehearth.presence_client:get_player_color(player_id)
   end

   self._visualization_node = _radiant.client.create_region_outline_node(
      self._render_entity:get_node(), region, radiant.util.to_color4(color, 48), radiant.util.to_color4(color, 200),
      'materials/transparent_with_depth.material.json', 'materials/debug_shape.material.json', 0)
end

return AceLandmarkRenderer
