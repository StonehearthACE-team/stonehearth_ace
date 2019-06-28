-- Adds a thought when the buff is added
local AddThoughtBuff = class()

function AddThoughtBuff:on_buff_added(entity, buff)
   local json = buff:get_json()
   if buff then
      radiant.entities.add_thought(entity, json.thought)
   end
end

return AddThoughtBuff
