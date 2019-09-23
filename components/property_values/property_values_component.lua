--[[
   this component considers appreciation of real estate assets and determines tax rates
   in accordance with federal, state, and municipal codes
   now I wish I'd put a real comment here so I knew what this was used for; I mean, obviously I can see what it does, but what uses it?
]]

local PropertyValues = class()

function PropertyValues:initialize()
   self._sv.properties = {}
end

function PropertyValues:get_property(property)
   return self._sv.properties[property]
end

function PropertyValues:set_property(property, value, replace)
   if not self._sv.properties[property] or replace ~= false then
      self._sv.properties[property] = value
      self.__saved_variables:mark_changed()
      return true
   end
end

return PropertyValues
