local AceCollectResourcesTutorialScenario = class()
local BaseScenario = require 'stonehearth.scenarios.basic_tutorial_scenario'

function AceCollectResourcesTutorialScenario:destroy()
   self:_remove_listeners()
   self:_destroy_bulletin()
   BaseScenario.__user_destroy(self)
end

return AceCollectResourcesTutorialScenario
