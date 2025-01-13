local Fixture = require 'stonehearth.components.building2.fixture'
local AceFixture = class()

function AceFixture:get_building()
   return self._sv._building
end

function AceFixture:set_entity_placed(entity, skip_event)
   local data = stonehearth.building:get_data(self._sv._bid)
   if data:get_owner_bid() ~= -1 then
      local owner = stonehearth.building:get_data(data:get_owner_bid(), data:get_owner_sub_bid())
      if owner.normal then
         entity:add_component('stonehearth:build2:fixture_renderer_tag')
         entity:get('stonehearth:build2:fixture_renderer_tag'):init(owner.normal)
      end
   end

   self._sv._fixture_entity = entity
   self._sv._waiting_ghost_id = nil
   self._sv._waiting_for_ghost_entity = nil
   self:_attach_entity_listeners()

   if not skip_event then
      radiant.events.trigger_async(self._sv._building, 'stonehearth:build2:building_fixture_progress', self._sv._uri, self:get_quality())
   end
end

function AceFixture:remove_placed_entity()
   if self._sv._fixture_entity then
      self._sv._fixture_entity:remove_component('stonehearth:build2:fixture_renderer_tag')
      -- ACE: also check if the fixture is parented to the world; if so, we need to pop it out to iconic
      -- based on the code in stonehearth:build2:structure._pre_destroy()
      local fixture = self._sv._fixture_entity
      if radiant.entities.get_parent(fixture) == radiant.entities.get_root_entity() then
         local location = radiant.entities.get_world_grid_location(fixture)
         if location then
            local extensible_object_comp = fixture:get_component('stonehearth_ace:extensible_object')
            if extensible_object_comp then
               extensible_object_comp:set_extension()
            end

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
