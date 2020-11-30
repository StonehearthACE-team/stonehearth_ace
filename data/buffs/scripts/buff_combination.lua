-- checks for a list of buffs when added and if one of them is present, remove it and itself and add a third buff.
local BuffCombination = class()

function BuffCombination:on_buff_added(entity, buff)
   local json = buff:get_json()
	self._tuning = json.script_info
	self._entity = entity
   self._buff = buff

	for _ , condition_buff in ipairs(self._tuning.check_for) do
		if radiant.entities.has_buff(self._entity, condition_buff) then
			self:_combine()
			break
		end
	end
end

function BuffCombination:_combine()	
	for _ , condition_buff in ipairs(self._tuning.check_for) do
		radiant.entities.remove_buff(self._entity, condition_buff)		
	end
	
	for _ , combined_buff in ipairs(self._tuning.combines_into) do
		radiant.entities.add_buff(self._entity, combined_buff)		
	end
	
	self._buff:destroy()		
end

return BuffCombination
