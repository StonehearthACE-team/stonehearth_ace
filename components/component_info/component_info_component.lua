--[[
   can contain specific information about that specific entity/component instance
   gets updated by any components that care
   can specify component data for it to hide generic or all info for select components
]]

local ComponentInfoComponent = class()

function ComponentInfoComponent:initialize()
   self._sv.components = {}
end



return ComponentInfoComponent