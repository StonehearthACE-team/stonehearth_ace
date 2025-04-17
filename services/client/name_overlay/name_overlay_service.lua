
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4
local RegionCollisionType = _radiant.om.RegionCollisionShape
local constants = stonehearth.constants.name_overlay

local NameOverlayService = class()

local log = radiant.log.create_logger('name_overlay_service')

function NameOverlayService:initialize()
   -- stonehearth.hotkey:register_hotkey('ui:toggle_names', function()
   --    log:debug('toggle_names hotkey pressed')
   --    self:toggle_names()
   --    return true
   -- end)
   -- stonehearth.hotkey:register_hotkey('ui:cycle_names', function()
   --    self:cycle_names()
   --    return true
   -- end)
   -- stonehearth.hotkey:register_hotkey('ui:toggle_workshop_icons', function()
   --    self:toggle_workshop_icons()
   --    return true
   -- end)
   -- stonehearth.hotkey:register_hotkey('ui:toggle_crop_icons', function()
   --    self:toggle_crop_icons()
   --    return true
   -- end)

   self._names_enabled = false
   self._name_type_index = 1
end

function NameOverlayService:get_enabled_names()
   return self._names_enabled and constants.NAME_TYPES[self._name_type_index]
end

function NameOverlayService:toggle_names()
   self._names_enabled = not self._names_enabled
   radiant.events.trigger(self, 'stonehearth_ace:name_overlay:names_toggled')
end

function NameOverlayService:cycle_names()
   self._name_type_index = self._name_type_index + 1
   if self._name_type_index > #constants.NAME_TYPES then
      self._name_type_index = 1
   end
   radiant.events.trigger(self, 'stonehearth_ace:name_overlay:name_type_index_changed', {name_type_index = self._name_type_index})
end

function NameOverlayService:toggle_workshop_icons()
end

function NameOverlayService:toggle_crop_icons()
end

return NameOverlayService
