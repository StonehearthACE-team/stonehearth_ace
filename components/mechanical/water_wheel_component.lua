local WaterWheelComponent = class()

function WaterWheelComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._json = json or {}
end

function WaterWheelComponent:activate()
   -- 
end

return WaterWheelComponent