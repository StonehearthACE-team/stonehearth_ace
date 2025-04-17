--[[
Based on the debug_shapes/box component and renderer.
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local TraceCategories = _radiant.dm.TraceCategories
local log = radiant.log.create_logger('name_overlay_renderer')
local NameOverlayRenderer = class()

local function _url_encode(s)
   s = string.gsub(s, "([^%w%.%- ])", function(c) return string.format("%%%02X", string.byte(c)) end)
   return string.gsub(s, " ", "+")
 end

function NameOverlayRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._render_entity = render_entity
   self._entity_node = render_entity:get_node()

   if datastore.__saved_variables then
      datastore = datastore.__saved_variables
   end

   self._datastore = datastore

   self._datastore_trace = self._datastore:trace('updating name_overlay')
      :on_changed(function()
            self:_update_name_overlay()
         end)

   local rcs = self._entity:get_component('region_collision_shape')
   if rcs then
      self._region_trace = rcs:trace_region('name_overlay renderer', TraceCategories.ASYNC_TRACE)
         :on_changed(function ()
               self:_update_name_overlay()
            end)
         :push_object_state()
   else
      -- If the entity doesn't have a region collision shape, create a default one for a hearthling's size.
      self._region = Region3()
      self._region:add_cube(Cube3(Point3(-0.5, 0, -0.5), Point3(0.5, 3, 0.5)))
   end

   -- self._grid_location_trace = radiant.entities.trace_location(self._entity, 'name_overlay renderer')
   --    :on_changed(function()
   --          self:_update_name_overlay()
   --       end)

   self._name_toggle_trace = radiant.events.listen(stonehearth_ace.name_overlay, 'stonehearth_ace:name_overlay:names_toggled', function()
         self:_update_name_overlay()
      end)

   self._name_type_index_trace = radiant.events.listen(stonehearth_ace.name_overlay, 'stonehearth_ace:name_overlay:name_type_index_changed', function()
         self:_update_name_overlay()
      end)
end

function NameOverlayRenderer:destroy()
   if self._text_node then
      self._text_node:destroy()
      self._text_node = nil
   end

   if self._overlay_node then
      self._overlay_node:destroy()
      self._overlay_node = nil
   end

   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   if self._region_trace then
      self._region_trace:destroy()
      self._region_trace = nil
   end

   -- if self._grid_location_trace then
   --    self._grid_location_trace:destroy()
   --    self._grid_location_trace = nil
   -- end

   if self._name_toggle_trace then
      self._name_toggle_trace:destroy()
      self._name_toggle_trace = nil
   end

   if self._name_type_index_trace then
      self._name_type_index_trace:destroy()
      self._name_type_index_trace = nil
   end
end

function NameOverlayRenderer:_update_name_overlay()
   if self._text_node then
      self._text_node:destroy()
   end

   if self._overlay_node then
      self._overlay_node:destroy()
   end

   local name_types = stonehearth_ace.name_overlay:get_enabled_names()
   if not name_types then
      return
   end

   local data = self._datastore:get_data()

   if not data or not data.category or not name_types[data.category] then
      return
   end

   local name = data.name
   local icon = data.icon
   local region = self._region or self._entity:get_component('region_collision_shape'):get_region():get():duplicate()
   local r_size = region:get_bounds():get_size()

   name = name or nil
   icon = icon or nil

   if name and name ~= '' then
      self._text_node = self._entity_node:add_text_node(name)
      --local location = radiant.entities.get_world_location(self._entity)
      self._text_node:set_position(Point3(0, r_size.y + 3, 0))
   end

   -- if icon and icon ~= '' then
   --    self._icon_node = self._entity_node:add_ui_billboard_node('tower_buffs', icon, 1, r_size.y + 1, 40, 40, -1, 0)
   -- end

   -- if icon then
   --    local player_color = stonehearth.presence_client:get_player_color(radiant.entities.get_player_id(self._entity))
   --    local text_color = player_color.x .. ',' .. player_color.y .. ',' .. player_color.z
   --    local url = 'stonehearth/stonehearth_ace/ui/game/name_overlay/name_overlay.html?textColor=' .. _url_encode(text_color)
   --    -- if name then
   --    --    url = url .. '&text=' .. _url_encode(name)
   --    -- end
   --    if icon then
   --       url = url .. '&icon=' .. _url_encode(icon)
   --    end

   --    self._overlay_node = self._entity_node:add_ui_billboard_node('name_overlay', url, 1, 1, 40, 40, -0.5, 1)
   -- end
end

return NameOverlayRenderer
