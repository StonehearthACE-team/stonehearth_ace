local ReduceHealthOnExpire = class()

function ReduceHealthOnExpire:on_buff_removed(entity, buff)
   if buff and buff:is_duration_expired() then
      local health = radiant.entities.get_health(entity)
      local script_info = buff:get_json().script_info
      local target_health = script_info and script_info.health or 0

      if target_health < health then
         radiant.entities.modify_health(entity, target_health - health, buff:get_source())
      end
   end
end

return ReduceHealthOnExpire
