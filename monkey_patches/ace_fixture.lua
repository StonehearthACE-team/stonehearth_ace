local Fixture = require 'stonehearth.components.building2.fixture'
local AceFixture = class()

AceFixture._ace_old_instabuild = Fixture.instabuild
function AceFixture:instabuild()
   self:_ace_old_instabuild()

   local entity = self._sv._fixture_entity
   local inventory = stonehearth.inventory:get_inventory(entity)
   if inventory then
      inventory:add_item(entity)
   end
end

return AceFixture
