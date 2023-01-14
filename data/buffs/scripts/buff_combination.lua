-- checks for a list of buffs when added and if one of them is present, remove it and itself and add a third buff.
local BuffCombination = class()

function BuffCombination:on_buff_added(entity, buff)
   self._tuning = buff:get_json().script_info
   self._entity = entity

   for _ , condition_buff in ipairs(self._tuning.check_for) do
      if radiant.entities.has_buff(self._entity, condition_buff) then
         self:_combine(buff)
         break
      end
   end
end

function BuffCombination:_combine(buff)	
   for _ , condition_buff in ipairs(self._tuning.check_for) do
      radiant.entities.remove_buff(self._entity, condition_buff)		
   end
   
   for _ , combined_buff in ipairs(self._tuning.combines_into) do
      radiant.entities.add_buff(self._entity, combined_buff, {
         source = buff:get_source(),
         source_player = buff:get_source_player(),
      })
   end
   
   buff:destroy()		
end

return BuffCombination
