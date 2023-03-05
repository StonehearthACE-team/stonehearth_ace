local AceAIComponent = class()

local log = radiant.log.create_logger('ai_component')

-- override just to add custom data
function AceAIComponent:set_status_text_key(key, data)
   self._sv.status_text_key = key
   if data and data['target'] then
      local entity = data['target']
      if type(entity) == 'string' then
         local catalog_data = stonehearth.catalog:get_catalog_data(entity)
         if catalog_data then
            data['target_display_name'] = catalog_data.display_name
            data['target_custom_name'] = ''
         end
      elseif entity and entity:is_valid() then
         data['target_display_name'] = radiant.entities.get_display_name(entity)
         data['target_custom_name']  = radiant.entities.get_custom_name(entity)
         -- add custom data
         data['target_custom_data']  = radiant.entities.get_custom_data(entity)
      end
      data['target'] = nil
   end
   self._sv.status_text_data = data
   self.__saved_variables:mark_changed()
end

function AceAIComponent:town_suspended()
   -- check if the entity is currently mounted and save that mount entity, then dismount
   local parent = radiant.entities.get_parent(self._entity)
   local mount_component = parent and parent:get_component('stonehearth:mount')
   --log:debug('%s town suspended, checking mounted status in %s...', self._entity, parent)
   if mount_component and mount_component:is_in_use() and mount_component:get_user() == self._entity then
      log:debug('%s is mounted in %s while town suspending; dismounting!', self._entity, parent)
      self._sv._suspended_mount = parent
      self._sv._suspended_mount_location = mount_component:get_dismount_location()
      mount_component:dismount()
   end
end

function AceAIComponent:town_continued()
   -- try to remount a formerly dismounted entity, if possible
   local mount = self._sv._suspended_mount
   
   if mount then
      local mount_component = mount:get_component('stonehearth:mount')
      if mount_component then
         if self._sv._suspended_mount_location then
            -- need to first move the entity to where it had been
            -- so when it later dismounts, it'll be in an appropriate location
            radiant.terrain.place_entity(self._entity, self._sv._suspended_mount_location)
         end
         mount_component:mount(self._entity)
      end
   end

   self._sv._suspended_mount = nil
   self._sv._suspended_mount_location = nil
end

return AceAIComponent
