local TrainingDummyComponent = class()

function TrainingDummyComponent:initialize()
	self._json = radiant.entities.get_json(self) or {}
end

function TrainingDummyComponent:create()
	self._is_create = true
end

return TrainingDummyComponent