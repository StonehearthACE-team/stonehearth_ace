local Fixture = require 'stonehearth.components.building2.fixture'
local AceFixture = class()

function AceFixture:remove_placed_entity()
   if self._sv._fixture_entity then
      self._sv._fixture_entity:remove_component('stonehearth:build2:fixture_renderer_tag')
      -- ACE: also check if the fixture is parented to the world; if so, we need to pop it out to iconic
      -- based on the code in stonehearth:build2:structure._pre_destroy()
      local fixture = self._sv._fixture_entity
      if radiant.entities.get_parent(fixture) == radiant.entities.get_root_entity() then
         local location = radiant.entities.get_world_grid_location(fixture)
         if location then
            radiant.terrain.remove_entity(fixture)
            radiant.entities.turn_to(fixture, 0)
            fixture:get('mob'):set_ignore_gravity(false)

            radiant.events.trigger(fixture, 'stonehearth:structure:pre_destroy', { fallback_location = location })

            local entity_forms = fixture:get('stonehearth:entity_forms')
            if entity_forms and entity_forms:get_iconic_entity() then
               fixture = entity_forms:get_iconic_entity()
            end

            radiant.terrain.place_entity(fixture, location)
         end
      end
   end

   self:_destroy_entity_listeners()
   self._sv._fixture_entity = nil
end

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
