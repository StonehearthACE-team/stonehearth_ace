local ZoneRenderer = require 'stonehearth.renderers.zone_renderer'
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local GrowerUnderfieldRenderer = class()

function GrowerUnderfieldRenderer:initialize(render_entity, datastore)
   self._datastore = datastore
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._node = self._entity_node:add_group_node('underfarm node')
   self._dirt_nodes = {}
   self._origin = radiant.entities.get_world_grid_location(self._entity)
   self._rotation = 0
   self._scale = 0.1

   local grower_underfield_data = radiant.entities.get_component_data(self._entity, 'stonehearth_ace:grower_underfield')
   self._tilled_dirt_model = grower_underfield_data.tilled_dirt

   self._zone_renderer = ZoneRenderer(render_entity)
      -- TODO: read these colors from json
      :set_designation_colors(Color4(142, 67, 35, 76), Color4(142, 67, 35, 76))
      :set_ground_colors(Color4(77, 62, 38, 10), Color4(77, 62, 38, 10))

   self._datastore_trace = self._datastore:trace_data('rendering grower underfield designation')
      :on_changed(
         function()
            self:_update()
         end
      )
      :push_object_state()
end

function GrowerUnderfieldRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end
   if self._node then
      self._node:destroy()
      self._node = nil
   end
   self._zone_renderer:destroy()
end

function GrowerUnderfieldRenderer:_update()
   local data = self._datastore:get_data()
   local size = data.size
   local items = {}

   local dirt_node_array = self:_update_and_get_dirt_node_array(data)
   self._zone_renderer:set_size(size)
   self._zone_renderer:set_current_items(items)
   self._zone_renderer:set_render_nodes(dirt_node_array)
end

function GrowerUnderfieldRenderer:_move_node(node, pt)
   local offset = self._origin:scaled(.1) + pt
   node:set_transform(offset.x, offset.y, offset.z, 0, self._rotation, 0, self._scale, self._scale, self._scale)
end

function GrowerUnderfieldRenderer:_create_node(pt, model)
   local node = _radiant.client.create_qubicle_matrix_node(self._node, model, 'dirt_plot', self._origin)
   self:_move_node(node, pt)
   return node
end

function GrowerUnderfieldRenderer:_get_dirt_node(x, y)
   local row = self._dirt_nodes[x]
   if not row then
      return nil
   end
   return row[y]
end

function GrowerUnderfieldRenderer:_set_dirt_node(x, y, node)
   local row = self._dirt_nodes[x]
   if not row then
      row = {}
      self._dirt_nodes[x] = row
   end
   row[y] = node
end

function GrowerUnderfieldRenderer:_update_and_get_dirt_node_array(data)
   local size_x = data.size.x
   local size_y = data.size.y
   local contents = data.contents
   local dirt_node_array = {}
   for x=1, size_x do
      for y=1, size_y do
         local dirt_plot = contents[x][y]
         if dirt_plot and dirt_plot.x ~= nil then -- need to check for nil for backward compatibility reasons
            local node = self:_get_dirt_node(x, y)
            if not node then
               local model = self._tilled_dirt_model
               node = self:_create_node(Point3(dirt_plot.x - 1.5, 0, dirt_plot.y - 1.5), model)
               self:_set_dirt_node(x, y, node)
            end
            table.insert(dirt_node_array, node)
         end
      end
   end
   return dirt_node_array
end

return GrowerUnderfieldRenderer
