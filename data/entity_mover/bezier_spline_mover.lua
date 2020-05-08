-- see "jacos bezier.js" in same directory

local Point3 = _radiant.csg.Point3

local BezierSplineMover = class()

local log = radiant.log.create_logger('bezier_spline_mover')

local get_weights = function(points)
   local weights = {}
   for i = 1, #points - 1 do
      table.insert(weights, points[i]:distance_to(points[i + 1]))
   end
   return weights
end

local get_dimension = function(points, dim)
   local values = {}
   for _, point in ipairs(points) do
      table.insert(values, point[dim])
   end
   return values
end

local get_points = function(xs, ys, zs)
   local points = {}
   for i = 1, #xs do
      table.insert(points, Point3(xs[i], ys[i], zs[i]))
   end
   return points
end

local Thomas4 = function(n, r, a, b, c, d)
   local p = {}

   -- the following array elements are not in the original matrix, so they should not have an effect
   a[0] = 0 -- outside the matrix
   c[n - 1] = 0 -- outside the matrix
   d[n - 2] = 0 -- outside the matrix
   d[n - 1] = 0 -- outside the matrix

   -- solves Ax=b with the Thomas algorithm (from Wikipedia)
   -- adapted for a 4-diagonal matrix. only the a[i] are under the diagonal, so the Gaussian elimination is very similar
   for i = 1, n - 1 do
      local m = a[i] / b[i - 1]
      b[i] = b[i] - m * c[i - 1]
      c[i] = c[i] - m * d[i - 1]
      r[i] = r[i] - m * r[i - 1]
   end
 
   p[n-1] = r[n-1] / b[n-1]
   p[n-2] = (r[n - 2] - c[n - 2] * p[n - 1]) / b[n - 2];
   for i = n - 3, 0, -1 do
      p[i] = (r[i] - c[i] * p[i + 1] - d[i] * p[i + 2]) / b[i]
   end
   
   return p
end

local computeControlPointsBigWThomas = function(K, W)
   local n = #K - 1
   
   --rhs vector
   local a, b, c, d, r = {}, {}, {}, {}, {}
   
   --left most segment
   a[0] = 0 -- outside the matrix
   b[0] = 2
   c[0] = -1
   d[0] = 0
   r[0] = K[1] + 0  -- add curvature at K0
   
   -- internal segments
   for i = 1, n - 1 do
      a[2*i-1] = 1*W[i + 1]*W[i + 1]
      b[2*i-1] = -2*W[i + 1]*W[i + 1]
      c[2*i-1] = 2*W[i]*W[i]
      d[2*i-1] = -1*W[i]*W[i]
      r[2*i-1] = K[i + 1] * ((-W[i + 1]*W[i + 1]+W[i]*W[i]))

      a[2*i] = W[i + 1]
      b[2*i] = W[i]
      c[2*i] = 0
      d[2*i] = 0 -- note: d[2n-2] is already outside the matrix
      r[2*i] = (W[i] + W[i + 1]) * K[i + 1]
   end
         
   -- right segment
   a[2*n-1] = -1
   b[2*n-1] = 2
   r[2*n-1] = K[n + 1] -- curvature at last point

   -- the following array elements are not in the original matrix, so they should not be used:
   c[2*n-1] = 0 -- outside the matrix
   d[2*n-2] = 0 -- outside the matrix
   d[2*n-1] = 0 -- outside the matrix

   -- solves Ax=b with the Thomas algorithm (from Wikipedia)
   local p = Thomas4(2*n, r, a, b, c, d)

   --re-arrange the array
   local p1, p2 = {}, {}
   for i = 0, n - 1 do
      table.insert(p1, p[2*i])
      table.insert(p2, p[2*i+1])
   end
   
   return p1, p2
end

-- distance is [0, 1]
local get_point_between = function(p1, p2, distance)
   return (p2 - p1) * distance + p1
end

local add_curve_points = function(points, p1, cp1, cp2, p2, num)
   --log:debug('adding curve points for: %s [%s, %s] %s', p1, cp1, cp2, p2)
   local last_point = p1
   local focus = get_point_between(p1, p2, 0.5)

   for i = 1, num do
      local dist = i / num
      local q1 = get_point_between(p1, cp1, dist)
      local q2 = get_point_between(cp1, cp2, dist)
      local q3 = get_point_between(cp2, p2, dist)
      local r1 = get_point_between(q1, q2, dist)
      local r2 = get_point_between(q2, q3, dist)
      local p = get_point_between(r1, r2, dist)

      -- store the last distance (may be used for speed adjustments) and normal (rolling)
      table.insert(points, {
         location = p,
         last_distance = last_point:distance_to(p),
         normal = focus - p
      })
      
      last_point = p
   end
end

function BezierSplineMover:__init(entity, mover)
   -- track destination entities; if they move between ticks, we'll need to recalculate everything
   self._entity = entity
   self._mover = mover
   self._points_per_segment = 10
   self._entity_traces = {}
   self:_track_destination_entities()
   self:_calculate()
end

function BezierSplineMover:destroy()
   self:_destroy_entity_traces()
end

function BezierSplineMover:_destroy_entity_traces()
   for _, trace in pairs(self._entity_traces) do

   end
   self._entity_traces = {}
end

function BezierSplineMover:_destroy_entity_trace(id)
   local trace = self._entity_traces[id]
   if trace then
      if trace.destroy_listener then
         trace.destroy_listener:destroy()
      end
      if trace.movement_listener then
         trace.movement_listener:destroy()
      end
   end
   self._entity_traces[id] = nil
end

function BezierSplineMover:_track_destination_entities()
   self:_destroy_entity_traces()

end

function BezierSplineMover:update(field, value)
   if field == 'destinations' then
      self._needs_recalculate = true
   end
end

function BezierSplineMover:move_on_game_loop(mover)
   if self._needs_recalculate then
      self._needs_recalculate = false
      self:_calculate()
   end

   self._mover:_move_directly(self._destinations, self._mover:_get_distance_per_gameloop())
   
   -- very important: need to tell the mover if we haven't reached the final destination yet!
   return #self._destinations > 0
end

function BezierSplineMover:_calculate()
   local points = {}
   table.insert(points, self._mover:_get_destination_point(self._entity))
   for _, destination in ipairs(self._mover:get_destinations()) do
      local p = self._mover:_get_destination_point(destination)
      if p ~= points[#points] then
         table.insert(points, p)
      end
   end
   --log:debug('points: %s', radiant.util.table_tostring(points))

   local weights = get_weights(points)
   --log:debug('weights: %s', radiant.util.table_tostring(weights))

   local x = get_dimension(points, 'x')
   local y = get_dimension(points, 'y')
   local z = get_dimension(points, 'z')
   --log:debug('x: %s\ny: %s\nz: %s', radiant.util.table_tostring(x), radiant.util.table_tostring(y), radiant.util.table_tostring(z))

   local px1, px2 = computeControlPointsBigWThomas(x, weights)
   --log:debug('px1: %s\npx2: %s', radiant.util.table_tostring(px1), radiant.util.table_tostring(px2))
   local py1, py2 = computeControlPointsBigWThomas(y, weights)
   --log:debug('py1: %s\npy2: %s', radiant.util.table_tostring(py1), radiant.util.table_tostring(py2))
   local pz1, pz2 = computeControlPointsBigWThomas(z, weights)
   --log:debug('pz1: %s\npz2: %s', radiant.util.table_tostring(pz1), radiant.util.table_tostring(pz2))

   local p1 = get_points(px1, py1, pz1)
   --log:debug('p1: %s', radiant.util.table_tostring(p1))
   local p2 = get_points(px2, py2, pz2)
   --log:debug('p2: %s', radiant.util.table_tostring(p2))

   -- now we have all the destination points (knots: 'points') and control points (two for each segment: 'p1' and 'p2')
   -- we need to use the de Casteljau algorithm to calculate N points along each segment
   local curve_points = {}
   for i = 1, #points - 1 do
      add_curve_points(curve_points, points[i], p1[i], p2[i], points[i + 1], self._points_per_segment)
   end
   --log:debug('destinations: %s', radiant.util.table_tostring(curve_points))

   self._destinations = curve_points
end

return BezierSplineMover
