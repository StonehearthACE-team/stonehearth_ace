--[[
connection json structure:
connector regions are typically a 2-voxel region, including one voxel inside the entity and another outside it
or the entire collision region (potentially with some uniform extension beyond it)
connectors can be configured to trace component regions (with optional modifications)

"stonehearth_ace:connection": {
   "type1": {
      "connectors": {
         "connector1": {
            "region": [
               {
                  "min": { "x": -1, "y": 0, "z": 0 },
                  "max": { "x": 1, "y": 1, "z": 1 }
               }
            ],
            "max_connections": 1,
            "region_intersection_threshold": 1
         },
         "connector2": {
            "region": [
               {
                  "min": { "x": 0, "y": 0, "z": 0 },
                  "max": { "x": 2, "y": 1, "z": 1 }
               }
            ],
            "max_connections": 1
         },
         "connector3": {
            "region_component": "region_collision_shape",
            "get_region_fn": "get_region", <-- optional, defaults to this
            "extrusions": {
               "x": [1, 1] <-- extrude the region in the x dimension by 1 voxel on each side
            }
            "max_connections": 1
         }
      },
      "max_connections": 1
   }
}
]]
local Region3 = _radiant.csg.Region3
local ConnectionUtils = require 'lib.connection.connection_utils'
local _update_entity_connection_data = ConnectionUtils._update_entity_connection_data

local log = radiant.log.create_logger('connection_component')
local ConnectionComponent = class()

-- TODO: apparently this versioning system is no longer used, so I'd have to manually set version and check on restore
-- for now just integrate the existing functions into restore
local VERSIONS = {
   ZERO = 0,
   V1 = 1,
   V2 = 2,
   V3 = 3
}

function ConnectionComponent:get_version()
   return VERSIONS.V3
end

function ConnectionComponent:fixup_post_load(old_save_data)
   -- just nuke the connected stats and let it automatically rebuild connections
   if old_save_data.version < VERSIONS.V3 then
      self._sv.connected_stats = {}
   end
end

function ConnectionComponent:initialize()
   self._connections = {}
   self._region_traces = {}
   self._extrusions_cache = {}
   self._sv.connected_stats = {}
   self._sv.dynamic_connections = {}
end

function ConnectionComponent:create()
   --self._sv.version = self:get_version()
end

-- hacky fixup_post_load implementation for now
function ConnectionComponent:restore()
   self._is_restore = true
   if not self._sv.version then
      self._sv.version = 0
   end
   if self._sv.version ~= self:get_version() then
      self:fixup_post_load(self._sv)
   end
end

-- this is performed in activate rather than post_activate so that all specific connection services can use it in post_activate
-- dynamic connection components should therefore create their regions in initialize/create or in their get_region function
function ConnectionComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   local version = self:get_version()
   if self._sv.version ~= version then
      self._sv.version = version
      self.__saved_variables:mark_changed()
   end
   
   local connected_stats
   if self._is_restore and next(self._sv.connected_stats) then
      connected_stats = self._sv.connected_stats
   end

   -- dynamic connections are in _sv only to remote to client
   -- we want to reset this every time so we can properly trace regions
   self._sv.dynamic_connections = {}
   self:_format_connections()
   stonehearth_ace.connection:register_entity(self._entity, self._connections, connected_stats)
end

function ConnectionComponent:destroy()
   log:debug('%s connection component destroyed', self._entity:get_id())
   for _, trace in pairs(self._region_traces) do
      if trace.trace then
         trace.trace:destroy()
      end
   end
   self._region_traces = nil

   stonehearth_ace.connection:unregister_entity(self._entity)
end

function ConnectionComponent:_get_connector_key(conn_type, name)
   return conn_type .. '|' .. name
end

-- returns a string key representing the extrusions table
function ConnectionComponent:_get_extrusions_key(extrusions)
   local key = '|'
   if extrusions then
      for _, dim in ipairs({'x', 'y', 'z'}) do
         local extrusion = extrusions[dim]
         if extrusion and #extrusion == 2 then
            key = key .. dim .. extrusion[1] .. ',' .. extrusion[2] .. '|'
         end
      end
   end

   return key
end

function ConnectionComponent:_get_region_trace(conn_type, name, connector, get_only)
   local component = connector.region_component
   local get_region_fn = connector.get_region_fn or 'get_region'
   local get_region_fn_args = connector.get_region_fn_args or (component == 'stonehearth_ace:dynamic_connection' and {conn_type, name}) or {}

   local key = component .. '.' .. get_region_fn
   if next(get_region_fn_args) then
      key = key .. '(' .. table.concat(get_region_fn_args, ', ') .. ')'
   end

   local trace = self._region_traces[key]
   if get_only then
      return trace
   end

   local extrusions = connector.extrusions
   local extrusions_key = self:_get_extrusions_key(extrusions)
   connector.extrusions_key = extrusions_key
   if not self._extrusions_cache[extrusions_key] then
      self._extrusions_cache[extrusions_key] = extrusions
   end

   if not trace then
      trace = {
         connectors = {},
         extrusion_regions = {
            [extrusions_key] = false
         },
      }
      self._region_traces[key] = trace
   end

   if trace.trace then
      -- if the trace already exists, check to see if the extrusions are also already registered
      if trace.extrusion_regions[extrusions_key] == nil then
         trace.extrusion_regions[extrusions_key] = false
         trace.update_region(extrusions_key)
      end
   else
      local comp = self._entity:get_component(component)
      local fn = comp and comp[get_region_fn]
      local region = fn and fn(comp, unpack(get_region_fn_args))
      if region then
         local update_region = function(opt_extrusions_key)
            trace.region = region:get()

            for extr_key, _ in pairs(trace.extrusion_regions) do
               if not opt_extrusions_key or extr_key == opt_extrusions_key then
                  local specific_region = trace.region
                  if extrusions then
                     for dim, args in pairs(extrusions) do
                        if #args == 2 then
                           specific_region = specific_region:extruded(dim, args[1], args[2])
                        end
                     end
                  end
                  trace.extrusion_regions[extr_key] = specific_region
               end
            end
         end
         update_region()

         connector.region = Region3(trace.extrusion_regions[extrusions_key])
         trace.update_region = update_region
         trace.trace = region:trace('dynamic connection region')
            :on_changed(function()
               if not self._entity:is_valid() then
                  trace.trace:destroy()
               else
                  update_region()
                  log:debug('updated %s trace region to %s', key, trace.region:get_bounds())
                  --trace.regions[extrusions_key]:optimize('dynamic connection region')

                  for _, conn in pairs(trace.connectors) do
                     log:debug('updating connector %s|%s|%s', self._entity, conn.type, conn.name)
                     conn.connector.region = Region3(trace.extrusion_regions[conn.connector.extrusions_key])

                     stonehearth_ace.connection:update_connector(self._entity, conn.type, conn.connection_max_connections, conn.name, conn.connector)
                  end

                  self.__saved_variables:mark_changed()
               end
            end)
      end

      trace.destroy = function()
         if trace.trace then
            trace.trace.destroy()
            trace.trace = nil
         end
         if self._region_traces then
            self._region_traces[key] = nil
         end
      end
   end

   return trace
end

function ConnectionComponent:_format_connections()
   local all_connections = {}

   for conn_type, connection in pairs(self._json) do
      all_connections[conn_type] = {
         max_connections = connection.max_connections,
         connectors = {}
      }
      for name, connector in pairs(connection.connectors) do
         local connector_copy = radiant.shallow_copy(connector)
         if connector.region then
            local region = Region3()
            region:load(connector.region)
            connector_copy.region = region
            connector_copy.region:optimize('connector region')

            all_connections[conn_type].connectors[name] = connector_copy
         elseif connector.region_component then
            -- if we already have 
            self:_setup_dynamic_connector(conn_type, connection.max_connections, name, connector_copy)
         end
      end
   end

   for conn_type, connection in pairs(self._sv.dynamic_connections) do
      local connection_data = all_connections[conn_type]
      if not connection_data then
         connection_data = {
            max_connections = connection.max_connections,
            connectors = {}
         }
         all_connections[conn_type] = connection_data
      end
      for name, connector in pairs(connection.connectors) do
         connection_data.connectors[name] = connector
      end
   end

   self._connections = all_connections
end

function ConnectionComponent:get_connections(conn_type)
   if conn_type then
      return self._connections[conn_type]
   else
      return self._connections
   end
end

function ConnectionComponent:get_connected_stats(conn_type)
   local type_data = {}

   for c_type, data in pairs(self._sv.connected_stats) do
      if not conn_type or c_type == conn_type then
         _update_entity_connection_data(type_data, { [c_type] = data })
      end
   end

   -- return nil if no connected stats
   return next(type_data) and type_data
end

function ConnectionComponent:_setup_dynamic_connector(conn_type, connection_max_connections, name, connector)
   local trace = self:_get_region_trace(conn_type, name, connector)
   local key = self:_get_connector_key(conn_type, name)
   trace.connectors[key] = {
      type = conn_type,
      connection_max_connections = connection_max_connections,
      name = name,
      connector = connector
   }

   local connections = self._sv.dynamic_connections[conn_type]
   if not connections then
      connections = {
         max_connections = connection_max_connections,
         connectors = {}
      }
      self._sv.dynamic_connections[conn_type] = connections
   end
   connections.connectors[name] = connector

   local connections = self._connections[conn_type]
   if not connections then
      connections = {
         max_connections = connection_max_connections,
         connectors = {}
      }
      self._connections[conn_type] = connections
   end
   connections.connectors[name] = connector

   self.__saved_variables:mark_changed()
end

function ConnectionComponent:update_dynamic_connector(conn_type, connection_max_connections, name, connector)
   self:_setup_dynamic_connector(conn_type, connection_max_connections, name, connector)

   stonehearth_ace.connection:update_connector(self._entity, conn_type, connection_max_connections, name, connector)
end

function ConnectionComponent:remove_dynamic_connector(conn_type, name)
   local connections = self._sv.dynamic_connections[conn_type]
   if connections then
      local connector = connections.connectors[name]
      if connector then
         -- if it had a dynamic region, remove the connector from that trace
         if connector.region_component then
            local trace = self:_get_region_trace(conn_type, name, connector, true)
            if trace then
               local key = self:_get_connector_key(conn_type, name)
               trace.connectors[key] = nil
               if not next(trace.connectors) then
                  trace.destroy()
               end
            end
         end

         connections.connectors[name] = nil
         stonehearth_ace.connection:remove_connector(self._entity, conn_type, name)
         self._sv.connected_stats[conn_type].connectors[name] = nil
         self.__saved_variables:mark_changed()

         connections = self._connections[conn_type]
         if connections then
            connections.connectors[name] = nil
         end
      end
   end
end

-- this is called by the connection service when this entity has any of its connectors change status
-- it may be called with just the type and conn_name to initialize the data structures
-- it may be called with just the type and the graph_id when it changes graphs and needs all connectors for that type to update graph_id
function ConnectionComponent:set_connected_stats(conn_type, conn_name, connected_to_id, graph_id, threshold)
   log:debug('[%s]:set_connected_stats(%s, %s, %s, %s, %s)', self._entity, conn_type, tostring(conn_name), tostring(connected_to_id), tostring(graph_id), tostring(threshold))
   local type_data = self._sv.connected_stats[conn_type]
   if not type_data then
      type_data = {connectors = {}, num_connections = 0, max_connections = self._connections[conn_type].max_connections}
      self._sv.connected_stats[conn_type] = type_data
   end

   if conn_name then
      local conn_data = type_data.connectors[conn_name]
      if not conn_data then
         conn_data = {connected_to = {}, num_connections = 0, max_connections = self._connections[conn_type].connectors[conn_name].max_connections}
         type_data.connectors[conn_name] = conn_data
      end

      if connected_to_id then
         local new_status = (graph_id or threshold) and {graph_id = graph_id, threshold = threshold or prev_status.threshold}
         local prev_status = conn_data.connected_to[connected_to_id]
         conn_data.connected_to[connected_to_id] = new_status
         if (prev_status ~= nil) ~= (new_status ~= nil) then
            local conn_modifier = (new_status and 1) or -1
            conn_data.num_connections = conn_data.num_connections + conn_modifier
            type_data.num_connections = type_data.num_connections + conn_modifier
         end
      end
   elseif graph_id then
      for name, connector in pairs(type_data.connectors) do
         for id, prev_status in pairs(connector.connected_to) do
            threshold = threshold or 0
            if radiant.util.is_a(prev_status, 'table') then
               threshold = prev_status.threshold
            end
            connector.connected_to[id] = {graph_id = graph_id, threshold = threshold}
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function ConnectionComponent:trace_data(reason)
   return self.__saved_variables:trace_data(reason)
end

return ConnectionComponent