-- modifies resources when added/removed
local ModifyResources = class()

function ModifyResources:on_buff_added(entity, buff)
   local exp_res = entity:get_component('stonehearth:expendable_resources')
   if not exp_res then
      return
   end

   local tuning = buff:get_json()
   self._resources = tuning.resources

   -- don't apply the modifications if the buff is being restored (they were already applied)
   if not buff._is_restore then
      for resource, data in pairs(self._resources) do
         self:_apply_resource_modification(exp_res, resource, data.on_added)
      end
   end
end

function ModifyResources:on_buff_removed(entity, buff)
   if entity and entity:is_valid() and self._resources then
      local exp_res = entity:get_component('stonehearth:expendable_resources')
      if not exp_res then
         return
      end

      local expired = buff and buff:is_duration_expired()

      for resource, data in pairs(self._resources) do
         if expired then
            self:_apply_resource_modification(exp_res, resource, data.on_naturally_removed)
         end

         if not expired then
            self:_apply_resource_modification(exp_res, resource, data.on_unnaturally_removed)
         end

         self:_apply_resource_modification(exp_res, resource, data.on_removed)
      end
   end
end

function ModifyResources:_apply_resource_modification(exp_res_comp, resource, modification)
   if modification then
      if modification.set_to then
         exp_res_comp:set_value(resource, modification.set_to)
      elseif modification.modify_by then
         exp_res_comp:modify_value(resource, modification.modify_by)
      end
   end
end

return ModifyResources
