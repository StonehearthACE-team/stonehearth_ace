-- maintains a list of all vine entities growing from a single parent
-- used for toggling harvest requests for all vines in a group at once

local resources_lib = require 'stonehearth_ace.lib.resources.resources_lib'

local VineGroup = class()

function VineGroup:initialize()
   self._sv.vines = {}
end

function VineGroup:add_vine(vine)
   self._sv.vines[vine:get_id()] = vine
   self.__saved_variables:mark_changed()
end

function VineGroup:remove_vine(id)
   local vine = self._sv.vines[id]
   self._sv.vines[id] = nil

   if vine then
      self.__saved_variables:mark_changed()

      -- if this was the last vine, self-destruct!
      if not next(self._sv.vines) then
         self:destroy()
      end
   end
end

function VineGroup:toggle_harvest_requests()
   resources_lib.toggle_harvest_requests(self._sv.vines)
end

return VineGroup
