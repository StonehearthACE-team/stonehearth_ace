local AceCollectResourcesTutorialScenario = class()
local BaseScenario = require 'stonehearth.scenarios.basic_tutorial_scenario'

function AceCollectResourcesTutorialScenario:initialize()
   BaseScenario.__user_initialize(self)
   self._sv._item_count = 0
   self._sv.quest_completed = false
   self._sv.bulletin = nil
end

function AceCollectResourcesTutorialScenario:destroy()
   self:_remove_listeners()
   self:_destroy_bulletin()
   BaseScenario.__userdestroy(self)
end

return AceCollectResourcesTutorialScenario

