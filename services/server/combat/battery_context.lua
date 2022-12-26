BatteryContext = class()

function BatteryContext:__init(attacker, target, damage, aggro_override, is_melee)
   self.attacker = attacker
   self.target = target
   self.damage = damage
   self.aggro_override = aggro_override
   self.is_melee = is_melee
end

return BatteryContext
