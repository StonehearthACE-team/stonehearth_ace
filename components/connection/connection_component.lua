--[[
connection json structure:
"connections": [
   "type1",
   "type2"
   ]
]]

local ConnectionComponent = class()

function ConnectionComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._connections = (json and json.connections) or {}
end

-- this is performed in activate rather than post_activate so that all specific connection services can use it in post_activate
function ConnectionComponent:activate()
   stonehearth_ace.connection:register_entity(self._entity)
end

function ConnectionComponent:destroy()
   stonehearth_ace.connection:unregister_entity(self._entity)
end

return ConnectionComponent