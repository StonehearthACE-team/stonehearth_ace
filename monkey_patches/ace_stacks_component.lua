local StacksComponent = require 'stonehearth.components.stacks.stacks_component'
local AceStacksComponent = class()

AceStacksComponent._ace_old_create = StacksComponent.create
function AceStacksComponent:create()
   local json = radiant.entities.get_json(self) or {}
   if json.default_stacks then
      self._sv.stacks = math.min(json.default_stacks, self._max_stacks)
   end
   self:_ace_old_create()
end

return AceStacksComponent
