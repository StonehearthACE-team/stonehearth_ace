--[[
   this service listens for relevant changes to the server connection service
   used for: render colors for connection types
]]

local Point3 = _radiant.csg.Point3
local ConnectionUtils = require 'lib.connection.connection_utils'

local combine_tables = ConnectionUtils.combine_tables
local combine_type_tables = ConnectionUtils.combine_type_tables

local log = radiant.log.create_logger('connection_client')

local ConnectionClientService = class()

function ConnectionClientService:initialize()
   self._connection_colors = {}

   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
         self:_setup_connection_types()
      end)
end

function ConnectionClientService:destroy()
   self:destroy_listeners()
end

function ConnectionClientService:destroy_listeners()

end

function ConnectionClientService:_setup_connection_types()
   _radiant.call_obj('stonehearth_ace.connection', 'get_connection_types_command')
      :done(function(response)
         for name, type in pairs(response.types) do
            local colors = {}
            colors.connected = Point3(unpack(type.connected_color)) or Point3(64, 240, 0)
            colors.disconnected = Point3(unpack(type.disconnected_color)) or Point3(colors.connected.x / 2, colors.connected.y / 2, colors.connected.z / 2)

            self._connection_colors[name] = colors
         end
      end)
end

function ConnectionClientService:get_connection_type_colors(type)
   return self._connection_colors[type]
end

return ConnectionClientService