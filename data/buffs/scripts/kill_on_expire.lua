local KillOnExpire = class()

function KillOnExpire:on_buff_removed(entity, buff)
   if buff and buff:is_duration_expired() then
      radiant.entities.kill_entity(entity)
   end
end

return KillOnExpire
