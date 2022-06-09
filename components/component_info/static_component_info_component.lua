--[[
   {
      "details": {
         "key1": "[i18n key that can include html]",
         "key2": "[i18n key that can include html]"
      }
   }
]]

local StaticComponentInfoComponent = class()

function StaticComponentInfoComponent:activate()
   local json = radiant.entities.get_json(self) or {}

   local ci_comp = self._entity:add_component('stonehearth_ace:component_info')
   ci_comp:remove_component_details('stonehearth_ace:static_component_info')
   
   if json.details then
      -- TODO: include entity unit_info data in i18n_data?
      local i18n_data = {}
      for name, detail in pairs(json.details) do
         ci_comp:set_component_detail('stonehearth_ace:static_component_info', name, detail, i18n_data)
      end
   end
end

return StaticComponentInfoComponent
