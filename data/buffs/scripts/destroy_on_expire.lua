local DestroyOnExpire = class()

function DestroyOnExpire:on_buff_removed(entity, buff)
   if buff and buff:is_duration_expired() then
      radiant.entities.destroy_entity(entity)
   end
end

return DestroyOnExpire
