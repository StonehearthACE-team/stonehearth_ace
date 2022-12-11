local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('portrait_renderer')

local AcePortraitRendererService = class()

function AcePortraitRendererService:_stage_scene(options, scene_root, camera)
   --log:debug('staging portrait scene with options: %s', radiant.util.table_tostring(options))
   local entity = options.entity
   if not (radiant.util.is_a(entity, Entity) and entity:is_valid()) then
      log:warning('non-entity passed in portrait render options: %s', tostring(options.entity))
      return
   end

   local render_entity = self:_add_existing_entity(scene_root, entity)
   if options.animation then
      render_entity:get_animation_controller():apply_custom_pose(options.animation, options.time or 0)
   end
   
   local camera_pos = nil
   local camera_look_at = nil
   local camera_fov = 64

   local portrait_data = radiant.entities.get_entity_data(entity, 'stonehearth:portrait')
   if options.type == 'custom' then
      local scale = self:_get_value(options.scale) or 0.1
      local cam_x = self:_get_value(options.cam_x) or 0
      local cam_y = self:_get_value(options.cam_y) or 0
      local cam_z = self:_get_value(options.cam_z) or 0
      local look_x = self:_get_value(options.look_x) or 0
      local look_y = self:_get_value(options.look_y) or 0
      local look_z = self:_get_value(options.look_z) or 0
      camera_fov = self:_get_value(options.fov) or 64

      render_entity:get_model():set_model_scale(scale)
      render_entity:get_skeleton():set_scale(scale)
      camera_pos = Point3(cam_x, cam_y, cam_z)
      camera_look_at = Point3(look_x, look_y, look_z)
   elseif options.type and portrait_data and portrait_data.portrait_types[options.type] then
      render_entity:get_model():set_model_scale(0.1)
      render_entity:get_skeleton():set_scale(0.1)

      -- If the entity specifies portrait setup for the given type, use that.
      local stage_data = portrait_data.portrait_types[options.type]
      camera_pos = self:_to_point3(stage_data.camera.pos)
      camera_look_at = self:_to_point3(stage_data.camera.look_at)
      
      -- ACE: added using a separate fov field to not suddenly take into account all the random base game ones
      if stage_data.camera.ace_fov then
         camera_fov = stage_data.camera.ace_fov
      end

   elseif options.type == 'headshot' then
      -- For legacy reasons, all the numbers below assume a scale of 0.1
      local scale = 0.1
      render_entity:get_model():set_model_scale(scale)
      render_entity:get_skeleton():set_scale(scale)
   
      -- For headshots, calculate the height of the camera based on the head bone of the entity.
      local camera_pos_y = 2.4
      local render_info = entity:get_component('render_info')
      if render_info then
         local animation_table_location = render_info:get_animation_table()
         if animation_table_location and animation_table_location:len() > 0 then
            local animation_table = radiant.resources.load_json(animation_table_location)
            local head_position = animation_table.skeleton.head
            camera_pos_y = head_position[3] * scale * 1.55
         end
      end
      camera_pos = Point3(20.4 * scale, camera_pos_y, -32.4 * scale)
      camera_look_at = Point3(0, camera_pos_y - 0.3, 0)
   else
      log:warning('invalid portrait type: %s', options.type)
      return
   end

   self:add_light(scene_root, {
      color =         Point3(0.75, 0.66, 0.75),
      ambient_color = Point3(0.35,  0.35, 0.35),
      -- Direction is in degrees with yaw and pitch as the first 2 params. Ignore 3rd param
      -- -180 yaw will have light going from -z to positive z
      direction =     Point3(10, 160, 0),
   })
   
   camera:set_is_orthographic(true)
   camera:set_position(camera_pos)
   camera:look_at(camera_look_at)
   -- This looks absurd (what does it mean to set a field-of-view on an orthographic projection!?)
   -- Basically, we create a perspective projection, and then wrap that in an AABB.  This sort of maps
   -- to our intuitions of what an fov is (bigger fov = more of the scene is visible), even if it
   -- would make a mathematician throw up a little.  Also, it's probably quite a bit easier to control
   -- the extents of the orthographic box with just one value (assuming constant near/far planes).
   camera:set_fov(camera_fov)
end

function AcePortraitRendererService:_get_value(value)
   if type(value) == 'string' then
      -- if the start is an underscore, remove it
      if string.sub(value, 1, 1) == '_' then
         value = string.sub(value, 2)
      end
      return tonumber(value)
   else
      return value
   end
end

return AcePortraitRendererService
