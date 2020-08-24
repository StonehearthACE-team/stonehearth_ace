--[[
   originally a monkey-patch to add base node (so it can be rendered relative to an entity)
   now overridden to provide support to vertical rulers (TODO: also improve text placement)
]]

local Mesh = _radiant.csg.Mesh
local Vertex = _radiant.csg.Vertex
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local LINE_WIDTH = 0.15
local ARROW_WIDTH = 0.5
local ARROW_HEIGHT = 0.8

local XYZRulerWidget = class()

function XYZRulerWidget:__init()
   self._padding = 1;
   self._margin = 1;
   self._line_color = Color4(0, 0, 0, 128)
   self._meshNormal = Point3(0, 1, 0)
   self._hidden = false
end

function XYZRulerWidget:destroy()
   self:_destroy_render_nodes()
end

function XYZRulerWidget:set_base_node(base_node)
   self._base_node = base_node
   return self
end

function XYZRulerWidget:set_points(start, finish, dimension, normal, label)
   -- (0, 0, 0) -> (-7, 0, 0)
   -- dimension = 'x'
   -- normal = (0, 0, 1)   -- TODO: sanitize?
   self._start = start
   self._finish = Point3(start)
   self._finish[dimension] = finish[dimension]
   self._start = self._start - Point3(0.5, 0, 0.5)
   self._finish = self._finish - Point3(0.5, 0, 0.5)

   self._normal = normal
   self._dimension = dimension
   self._dim_vector = self._finish - self._start
   self._dim_vector:normalize()
   self._label = label
   self:_recreate_render_node(self._label)

   
   -- self._normal = normal
   -- self._label = label
   -- self._dimension = dimension or (normal.x == 0 and 'x' or 'z')
   -- self._start = start + normal + Point3(-0.5, 0.01, -0.5)
   -- self._finish = finish + normal + Point3(0.5, 0.01, 0.5)
   -- if normal.z < 0 then
   --    local offset = self:_get_height() - 1
   --    self._start.z = self._start.z - offset
   --    self._finish.z = self._finish.z - offset
   -- end
   -- self:_recreate_render_node(self._label);
end

function XYZRulerWidget:set_color(color)
   self._line_color = color
end

function XYZRulerWidget:hide()
   if not self._hidden then
      self:_destroy_render_nodes()
      self._hidden = true
   end
end

function XYZRulerWidget:show()
   if self._hidden then
      self._hidden = false
      self:_recreate_render_node(self._label);
   end
end

function XYZRulerWidget:_destroy_render_nodes()
   if self._render_node then
      self._render_node:destroy()
      self._render_node = nil
   end
   if self._text_node then
      self._text_node:destroy()
      self._text_node = nil
   end
end

function XYZRulerWidget:_add_quad(mesh, color, p0, p1, p2, p3)
   local function push(point)
      return mesh:add_vertex(Vertex(point, self._meshNormal, color))
   end

   local indices = {}
   indices[0] = push(p0)
   indices[1] = push(p1)
   indices[2] = push(p2)
   indices[3] = push(p3)

   mesh:add_index(indices[0])      -- first triangle
   mesh:add_index(indices[1])
   mesh:add_index(indices[2])

   mesh:add_index(indices[0])      -- second triangle
   mesh:add_index(indices[2])
   mesh:add_index(indices[3])

   -- the right-hand rule is a pain, so just draw the triangles in both directions so we guarantee that it renders with our given normal
   mesh:add_index(indices[2])      -- first triangle back
   mesh:add_index(indices[1])
   mesh:add_index(indices[0])

   mesh:add_index(indices[3])      -- second triangle back
   mesh:add_index(indices[2])
   mesh:add_index(indices[0])
end

function XYZRulerWidget:_add_triangle(mesh, color, p0, p1, p2)
   local function push(point)
      return mesh:add_vertex(Vertex(point, self._meshNormal, color))
   end

   local indices = {}
   indices[0] = push(p0)
   indices[1] = push(p1)
   indices[2] = push(p2)

   mesh:add_index(indices[0])
   mesh:add_index(indices[1])
   mesh:add_index(indices[2])

   -- the right-hand rule is a pain, so just draw the triangles in both directions so we guarantee that it renders with our given normal
   mesh:add_index(indices[2])       -- back
   mesh:add_index(indices[1])
   mesh:add_index(indices[0])
end

function XYZRulerWidget:_get_length()
   return math.abs(self._finish[self._dimension] - self._start[self._dimension])
end

function XYZRulerWidget:_get_height()
   return self._padding + self._margin
end

function XYZRulerWidget:_recreate_render_node(label)
   self:_destroy_render_nodes()

   if self._hidden then
      return
   end

   local w = 1
   if self:_get_length() <= 1 then
      return
   end

   local forward = _radiant.renderer.get_camera():get_forward()
   -- move the points slightly closer to the camera to avoid z-fighting in existing rendered surfaces
   local meshNormal = Point3.unit_y
   if self._dimension == 'y' then
      if self._normal.x == 0 then
         meshNormal = Point3(forward.x >= 0 and 1 or -1, 0, 0)
      else
         meshNormal = Point3(0, 0, forward.z >= 0 and 1 or -1)
      end
   end

   local start = self._start + meshNormal * 0.01
   local finish = self._finish + meshNormal * 0.01
   self._meshNormal = meshNormal
   

   local mesh = Mesh()
   local node = self._base_node or RenderRootNode

   --[[
      we have defined a start location and a finish location forming a single-dimensional line, along with a directional unit vector for that line and a normal
      (the mesh normal is the third dimension, pointing toward the camera)

      "close" means nearer to zero in the normal direction; "far" means further from zero in the normal direction
      "in" means nearer to the bounds start and finish; "out" means further outside their bounds
      the rule has six rendered parts:
         - start boundary line (narrow quad)
            [start-in-close, start-out-close, start-out-far, start-in-far]
         - start arrow (triangle)
         - length line (narrow quad)
            [start-in-close, start-in-far, finish-in-far, finish-in-close]
         - text label
            [avg(start + finish) + normal / 2]
         - finish arrow (triangle)
         - finish boundary line (narrow quad)
            [finish-in-close, finish-out-close, finish-out-far, finish-in-far]
   ]]
   
   -- start boundary line (narrow quad)
   self:_add_quad(mesh, self._line_color,
         start + self._dim_vector * LINE_WIDTH,
         start,
         start + self._normal * w,
         start + self._normal * w + self._dim_vector * LINE_WIDTH
      )

   -- finish boundary line (narrow quad)
   self:_add_quad(mesh, self._line_color,
         finish - self._dim_vector * LINE_WIDTH,
         finish,
         finish + self._normal * w,
         finish + self._normal * w - self._dim_vector * LINE_WIDTH
      )

   -- length line (narrow quad)
   local offset = self._dim_vector * (ARROW_HEIGHT + LINE_WIDTH)
   local start_center = start + offset + self._normal * 0.5 * w
   local finish_center = finish - offset + self._normal * 0.5 * w
   local half_width_vector = self._normal * (LINE_WIDTH / 2)
   self:_add_quad(mesh, self._line_color,
         start_center - half_width_vector,
         start_center + half_width_vector,
         finish_center + half_width_vector,
         finish_center - half_width_vector
      )

   -- start arrow (triangle)
   start_center = start + self._dim_vector * LINE_WIDTH + self._normal * 0.5 * w
   half_width_vector = self._normal * (ARROW_WIDTH / 2)
   local height_vector = self._dim_vector * ARROW_HEIGHT
   self:_add_triangle(mesh, self._line_color,
         start_center,
         start_center + height_vector + half_width_vector,
         start_center + height_vector - half_width_vector
      )

   -- finish arrow (triangle)
   finish_center = finish - self._dim_vector * LINE_WIDTH + self._normal * 0.5 * w
   self:_add_triangle(mesh, self._line_color,
         finish_center,
         finish_center - height_vector + half_width_vector,
         finish_center - height_vector - half_width_vector
      )

   self._render_node = _radiant.client.create_mesh_node(node, mesh)
   self._render_node:set_can_query(false)
                    :set_material('materials/transparent_box_nodepth.material.json')

   if label then
      self._text_node = node:add_text_node(label)
      self._text_node:set_position((start + finish) / 2 + self._normal * 0.5 * w + Point3.unit_y)
   end
end

return XYZRulerWidget
