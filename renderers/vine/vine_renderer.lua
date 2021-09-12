local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local VineRenderer = class()
local log = radiant.log.create_logger('vine.renderer')

local _rotations = {
   ['x-'] = 90,
   ['z+'] = 180,
   ['x+'] = 270,
   ['z-'] = 0
}

function VineRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('vine node')

   self._datastore = datastore
   self._vine_nodes = {}
   self._facing = radiant.entities.get_facing(self._entity)
   self._highlighted_vines = {}

   self._selection_listener = radiant.events.listen(radiant, 'stonehearth:selection_changed', function()
      self:_check_selection()
   end)

   self._gameplay_settings_changed = radiant.events.listen(radiant, 'stonehearth_ace:client_config_changed', function()
      self:_on_gameplay_setting_changed()
   end)
   self:_on_gameplay_setting_changed()

   self._datastore_trace = self._datastore:trace('drawing vines')
                                          :on_changed(function ()
                                                self:_update_render()
                                             end)
                                          :push_object_state()
end

function VineRenderer:destroy()
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   if self._datastore_trace and self._datastore_trace.destroy then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
   if self._selection_listener then
      self._selection_listener:destroy()
      self._selection_listener = nil
   end
   self:_destroy_group_trace()
end

function VineRenderer:_destroy_vine_nodes()
   for _, node in pairs(self._vine_nodes) do
      node:destroy()
   end
   self._vine_nodes = {}
end

function VineRenderer:_destroy_group_trace()
   if self._vine_group_trace and self._vine_group_trace.destroy then
      self._vine_group_trace:destroy()
      self._vine_group_trace = nil
   end
end

function VineRenderer:_update_group_highlight_trace(group)
   if group ~= self._vine_group then
      self:_destroy_group_trace()
      if group then
         self._vine_group_trace = group:trace('vine group members changed')
                                          :on_changed(function ()
                                                self._vine_group_data = group:get_data()
                                                self:_update_group_highlights()
                                             end)
                                          :push_object_state()
      end
   end
end

function VineRenderer:_on_gameplay_setting_changed()
   self._highlight_vine_group = stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'highlight_entire_vine_on_select')
   self:_update_group_highlights()
end

function VineRenderer:_check_selection()
   local selected = stonehearth.selection:get_selected()
   local is_selected = selected and selected:get_id() == self._entity:get_id()
   if is_selected ~= self._selected then
      self._selected = is_selected
      self:_update_group_highlights()
   end
end

function VineRenderer:_update_group_highlights()
   local vines = self._vine_group_data and self._vine_group_data.vines
   if not vines then
      return
   end

   local should_highlight = self._selected and self._highlight_vine_group

   -- go through all the vines and hilight them if they
   -- are not already hilighted.
   for id, vine in pairs(vines) do
      local needs_hilight = should_highlight and not self._highlighted_vines[id]
      if needs_hilight then
         local hilight_request = stonehearth.hilight:hilight_entity(vine)
         self._highlighted_vines[id] = hilight_request
      end
   end

   -- unhilight any vines that are no longer there
   for id, member in pairs(self._highlighted_vines) do
      local needs_unhilight = not should_highlight or not vines[id]
      if needs_unhilight then
         local hilight_request = self._highlighted_vines[id]
         self._highlighted_vines[id] = nil
         hilight_request:destroy()
      end
   end
end

function VineRenderer:_update_render()
   self:_destroy_vine_nodes()
   
   local data = self._datastore:get_data()
   local options = data.render_options
   local render_dirs = data.render_directions
   local casts_shadows = data.casts_shadows
   if not render_dirs or not next(render_dirs) then
      return
   end

   self:_update_group_highlight_trace(data.vine_group)

   local entity_node_pos = self._entity_node:get_position()
   self._entity_node:set_aabb(Cube3(Point3.zero + entity_node_pos, Point3.one + entity_node_pos))

   --log:error('render_directions: %s', radiant.util.table_tostring(render_dirs))
   for dir, _ in pairs(render_dirs) do
      if dir == 'y+' then
         self:_create_nodes(options.faces.top, 0, casts_shadows)
      elseif dir == 'y-' then
         self:_create_nodes(options.faces.bottom, 0, casts_shadows)
      else
         self:_create_nodes(options.faces.side, _rotations[dir] or 0, casts_shadows)
      end
   end
end

function VineRenderer:_create_nodes(options, rotation, casts_shadows)
   -- if this node data is an array, process through and create each node
   if not options.model then
      -- is there a problem with seasons for this biome?
      log:error('no model specified for node; invalid season?')
   elseif type(options.model) == 'string' then
      self:_create_node(options, {model = options.model}, rotation, casts_shadows)
   elseif type(options.model.model) == 'string' then
      self:_create_node(options, options.model, rotation, casts_shadows)
   elseif #options.model > 0 then
      for _, model in ipairs(options.model) do
         self:_create_node(options, model, rotation, casts_shadows)
      end
   end
end

function VineRenderer:_create_node(options, model, rotation, casts_shadows)
   if options and model.model then
      rotation = (360 - self._facing + rotation) % 360
      local origin = model.origin or options.origin or Point3.zero
      local scale = model.scale or options.scale or 0.1
      local material = model.material or options.material or 'materials/voxel.material.json'

      local node = _radiant.client.create_qubicle_matrix_node(self._node, model.model, 'background',
            Point3(origin.x, origin.y, origin.z))
      if node then
         --node:set_casts_shadows(casts_shadows)
         node:set_transform(0, 0, 0, 0, rotation, 0, scale, scale, scale)
         node:set_material(material)
         --node:set_visible(true)
         table.insert(self._vine_nodes, node)
      else
         --log:error('nil result from create_qubicle_matrix_node "%s" with rotation %s', model, rotation)
      end
   end
end

return VineRenderer
