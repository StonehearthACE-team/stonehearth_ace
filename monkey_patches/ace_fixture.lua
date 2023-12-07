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

function AceFixture:_on_pre_transform(args)
   if args.options.destroy_entity == false then
      return
   end

   -- if the fixture entity is getting transformed (e.g., herbalist exploration garden),
   -- we need to make sure we destroy the listeners on the old entity and attach them to the new one
   -- and set up any other data that needs to be transferred
   self:_destroy_entity_listeners()
   self._sv._fixture_entity:remove_component('stonehearth:build2:fixture_renderer_tag')
   self._sv._fixture_entity = nil

   if args.transformed_form then
      self:set_entity_placed(args.transformed_form, true)
   end
end

function AceFixture:_attach_entity_listeners()
   self:_destroy_entity_listeners()

   self._killed_listener = radiant.events.listen_once(self._sv._fixture_entity, 'stonehearth:kill_event', self, self._on_killed)
   self._pre_transform_listener = radiant.events.listen(self._sv._fixture_entity, 'stonehearth_ace:transform:pre_transform', self, self._on_pre_transform)
end

AceFixture._ace_old__destroy_entity_listeners = Fixture._destroy_entity_listeners
function AceFixture:_destroy_entity_listeners()
   self:_ace_old__destroy_entity_listeners()

   if self._pre_transform_listener then
      self._pre_transform_listener:destroy()
      self._pre_transform_listener = nil
   end
end

return AceFixture
