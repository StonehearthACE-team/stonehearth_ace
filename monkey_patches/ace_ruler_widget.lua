local Mesh = _radiant.csg.Mesh
local Point3 = _radiant.csg.Point3

local LINE_WIDTH = 0.15
local ARROW_WIDTH = 0.8
local ARROW_HEIGHT = 0.5

local AceRulerWidget = class()

function AceRulerWidget:set_base_node(base_node)
   self._base_node = base_node
   return self
end

function AceRulerWidget:_recreate_render_node(label)
   self:_destroy_render_nodes()

   if self._hidden then
      return
   end

   local w = self:_get_width()
   local h = self:_get_height()
   if w <= 1 then
      return
   end

   local mesh = Mesh()
   local node = self._base_node or RenderRootNode

   -- the line on the left and right
   self:_add_quad(mesh, 0, 0, LINE_WIDTH, h, self._line_color)
   self:_add_quad(mesh, w - LINE_WIDTH, 0, LINE_WIDTH, h, self._line_color)

   -- line through the center
   self:_add_quad(mesh, LINE_WIDTH + ARROW_WIDTH,
                        self._padding - (LINE_WIDTH / 2),
                        w - ((LINE_WIDTH + ARROW_WIDTH) * 2),
                        LINE_WIDTH,
                        self._line_color)
   -- left arrow
   self:_add_triangle(mesh, Point3(LINE_WIDTH, 0, self._padding),
                            Point3(LINE_WIDTH + ARROW_WIDTH, 0, self._padding + (ARROW_HEIGHT / 2)),
                            Point3(LINE_WIDTH + ARROW_WIDTH, 0, self._padding - (ARROW_HEIGHT / 2)),
                            self._line_color)
   -- right arrow
   self:_add_triangle(mesh, Point3(w - LINE_WIDTH, 0, self._padding),
                            Point3(w - LINE_WIDTH- ARROW_WIDTH, 0, self._padding - (ARROW_HEIGHT / 2)),
                            Point3(w - LINE_WIDTH- ARROW_WIDTH, 0, self._padding + (ARROW_HEIGHT / 2)),
                            self._line_color)

   self._render_node = _radiant.client.create_mesh_node(node, mesh)
   self._render_node:set_can_query(false)
                    :set_material('materials/transparent_box_nodepth.material.json')

   if label then
      self._text_node = node:add_text_node(label)
      self._text_node:set_position((self._start + self._finish) / 2)
   end
end

return AceRulerWidget
