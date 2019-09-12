local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local validator = radiant.validator
--local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local FenceCallHandler = class()

local FENCE_POST = 'fence_post'
local FENCE_END_SINGLE = 'fence_end_single'
local FENCE_END_DOUBLE = 'fence_end_double'

local log = radiant.log.create_logger('fence_call_handler')

local _sign = function(x)
   if x < 0 then
      return -1
   elseif x > 0 then
      return 1
   else
      return 0
   end
end

local _create_fence_nodes = function(pattern, start_location, end_location, facing, fn_create_node)
   local min_x = start_location.x
   local max_x = end_location.x
   local min_z = start_location.z
   local max_z = end_location.z
   local y = start_location.y

   local step_x = _sign(max_x - min_x)
   local step_z = _sign(max_z - min_z)

   --log:debug('x: %s -> %s, %s', min_x, max_x, step_x)
   --log:debug('z: %s -> %s, %s', min_z, max_z, step_z)

   local index = 1
   local pattern_index = 1
   local length = 0
   local last_was_end = false

   -- we can't do simple for loops, because fences can take up more or less than one voxel because it's stupid!
   -- (if only everyone just used my fence component, each style of fence would only require a single entity!)
   local x = min_x
   local z = min_z

   while x * step_x <= max_x * step_x and z * step_z <= max_z * step_z do
      local uri = pattern[pattern_index]
      local fence_data = radiant.entities.get_entity_data(uri, 'stonehearth_ace:fence_data') or {}
      local is_end = fence_data.type == 'end'
      local this_length = math.max(1, fence_data.length or 1)
      if not is_end and last_was_end then
         this_length = this_length - 1
      end
      last_was_end = is_end
      length = length + this_length

      --log:debug('placing %s, length = %s, this_length = %s', uri, length, this_length)

      if this_length < 1 then
         x = x - step_x
         z = z - step_z
         length = length + 1
      else
         for i = 1, math.floor(this_length / 2) do
            x = x + step_x
            z = z + step_z
            length = length - 1
         end
      end

      if x * step_x > max_x * step_x or z * step_z > max_z * step_z then
         break
      end

      fn_create_node(index, uri, Point3(x, y, z), (facing * 90) % 360)
      pattern_index = index % #pattern + 1
      index = index + 1

      for i = 1, math.floor(length) do
         x = x + step_x
         z = z + step_z
         length = length - 1
      end

      if step_x == 0 and step_z == 0 then
         break
      end
   end
end

function FenceCallHandler:choose_fence_location_command(session, response, pattern)
   validator.expect_argument_types({'table'}, pattern)
   
   local render_nodes = {}
   local destroy_render_nodes = function(through_index)
      for i = #render_nodes, through_index or 1, -1 do
         local node = table.remove(render_nodes, i)
         if radiant.util.is_a(node, Entity) then
            radiant.entities.destroy_entity(node)
         else
            node:destroy()
         end
      end
   end

   local axis = 0
   local facing = 2
   local location
   local determine_fence_line = function(box, start_location)
      local size_x = box.max.x - box.min.x
      local size_z = box.max.z - box.min.z
      
      local end_x = box.max.x - 1
      local end_z = box.max.z - 1

      -- don't change axis if it's now a square; only if one dimension is longer than the other
      if size_x > size_z then
         axis = 0
      elseif size_z > size_x then
         axis = 3
      end
      
      facing = 2
      if end_x == start_location.x then
         end_x = box.min.x
         if axis == 0 then
            facing = 0
         end
      end
      if end_z == start_location.z then
         end_z = box.min.z
         if axis == 3 then
            facing = 0
         end
      end

      local end_location
      if axis == 0 then
         -- if it's along x
         end_location = Point3(end_x, start_location.y, start_location.z)
      else
         -- if it's along z
         end_location = Point3(start_location.x, start_location.y, end_z)
      end

      --log:debug('determine_fence_line: [%s] => %s -> %s', box, start_location, end_location)
      return start_location, end_location
   end

   -- TODO: allow for the start location to be occupied by an existing entity, and start the fence with the second index
   stonehearth.selection:select_designation_region('fence_region_selector')
      :set_min_size(1)
      :set_max_size(100)
      :require_unblocked(false)
      :use_manual_marquee(function(xz_region_selector, box, start_location, stabbed_normal)
            -- determine the actual region for the fence from what's been drawn
            local prev_facing = axis + facing
            local start_loc, end_loc = determine_fence_line(box, start_location)
            -- then go through and create render nodes for the pattern along that line
            if prev_facing ~= (axis + facing) or location ~= start_location then
               location = start_location
               destroy_render_nodes()
            end
            local num_nodes = #render_nodes
            local last_index = 1
            
            _create_fence_nodes(pattern, start_loc, end_loc, axis + facing, function(index, uri, location, rotation)
                  -- simplest to just create a full client entity; a single node might not encompass the full model, and would involve more parsing
                  last_index = index
                  if index > num_nodes then
                     log:debug('placing %s at %s facing %s', uri, location, rotation)
                     local entity = radiant.entities.create_entity(uri)
                     radiant.terrain.place_entity_at_exact_location(entity, location, {force_iconic = false})
                     entity:add_component('mob'):turn_to(rotation)
                     table.insert(render_nodes, entity)
                  end
               end)
            
            if last_index < num_nodes then
               destroy_render_nodes(last_index + 1)
            end
         end)
      :set_can_contain_entity_filter(function(entity)
            for _, render_entity in ipairs(render_nodes) do
               if render_entity == entity then
                  return true
               end
            end
            return false
         end)
      :set_cursor('stonehearth:cursors:fence')
      :done(
         function(selector, box, start_location)
            local start_loc, end_loc = determine_fence_line(box, start_location)
            
            _radiant.call('stonehearth_ace:build_fence_command', pattern, start_loc, end_loc, axis + facing)
               :done(
                  function(r)
                     response:resolve({})
                  end
               )
               :always(
                  function()
                     selector:destroy()
                  end
               )
         end
      )
      :fail(
         function(selector)
            selector:destroy()
            response:reject('no region')
         end
      )
      :always(function()
            destroy_render_nodes()
         end)
      :go()
end

function FenceCallHandler:build_fence_command(session, response, pattern, start_location, end_location, facing)
   validator.expect_argument_types({'table', 'Point3', 'Point3', 'number'}, pattern, start_location, end_location, facing)

   local player_id = session.player_id
   local town = stonehearth.town:get_town(player_id)
   if town then
      local ghosts = {}
      _create_fence_nodes(pattern, start_location, end_location, facing, function(index, uri, location, rotation)
            local placement_info = {
               location = location,
               normal = Point3(0, 1, 0),
               rotation = rotation,
            }
            local ghost_entity = town:place_item_type(uri, nil, placement_info)
            if ghost_entity then
               local uri_ghosts = ghosts[uri]
               if not uri_ghosts then
                  uri_ghosts = {}
                  ghosts[uri] = uri_ghosts
               end
               table.insert(uri_ghosts, ghost_entity)
            end
         end)

      for uri, uri_ghosts in pairs(ghosts) do
         local player_jobs = stonehearth.job:get_jobs_controller(player_id)
         local order = player_jobs:request_craft_product(uri, #uri_ghosts)
         for _, ghost in ipairs(uri_ghosts) do
            ghost:add_component('stonehearth_ace:transform'):set_craft_order(order)
         end
      end
   end

   response:resolve({})
end

return FenceCallHandler
