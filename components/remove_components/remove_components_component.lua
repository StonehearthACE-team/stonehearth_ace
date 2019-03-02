--[[
   this component is used to remove other components on load
   e.g., your old version of an entity had a component that it no longer has
   so old saves with that old version have the component and it needs to be removed
]]

local RemoveComponentsComponent = class()

function RemoveComponentsComponent:initialize()
   self._json = radiant.entities.get_json(self)
end

function RemoveComponentsComponent:post_activate()
   self:_try_removing()
   -- then remove this component because it's done its job
   self._entity:remove_component('stonehearth_ace:remove_components')
end

-- component removal seemingly can't happen before the post_activate stage
function RemoveComponentsComponent:_try_removing()
   if self._json and self._json.components then
      for component, remove in pairs(self._json.components) do
         self._entity:remove_component(component)
      end
   end
end

return RemoveComponentsComponent