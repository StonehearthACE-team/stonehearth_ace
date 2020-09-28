local RemoveBuffOnExpire = class()

function RemoveBuffOnExpire:on_buff_removed(entity, buff)
   if buff and buff:is_duration_expired() then
      local tuning = buff:get_json()
      if tuning and tuning.buff_removed_on_expire then
         radiant.entities.remove_buff(entity, tuning.buff_removed_on_expire)
      end
   end
end

return RemoveBuffOnExpire
