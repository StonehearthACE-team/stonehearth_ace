local build_util = require 'stonehearth.lib.build_util'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local ItemPlacer = require 'stonehearth.services.client.build_editor.item_placer'
local Entity = _radiant.om.Entity
local validator = radiant.validator

--local PlaceItemCallHandler = require 'stonehearth.call_handlers.place_item_call_handler'
local AcePlaceItemCallHandler = class()

local log = radiant.log.create_logger('place_item_call_handler')

local function get_root_entity(item)
   if not item or not radiant.util.is_a(item, Entity) or not item:is_valid() then
      return
   end

   local iconic_form = item:get_component('stonehearth:iconic_form')
   if iconic_form then
      item = iconic_form:get_root_entity()
   end
   local ghost_form = item:get_component('stonehearth:ghost_form')
   if ghost_form then
      item = ghost_form:get_root_entity()
   end

   local entity_forms = item:get_component('stonehearth:entity_forms')
   if entity_forms then
      return item, entity_forms
   end
end

function AcePlaceItemCallHandler:choose_place_item_type_location(session, response, item_to_place, quality, transactional, options)
   validator.expect_argument_types({'string', validator.optional('number'), validator.optional('boolean'), validator.optional('table')},
         item_to_place, quality, transactional, options)

   -- This will register the tool; no need to hold on to the variable....
   local item_placer = ItemPlacer():go(session, response, item_to_place, quality, transactional, options)
end

-- ACE: don't destroy the old one and create a new one, that's insane
-- just remove the existing one from the world and place its iconic at that location
-- (and "reset" health/debuffs on the entity)
function AcePlaceItemCallHandler:undeploy_golem(session, response, item)
   validator.expect_argument_types({'Entity'}, item)

   -- check and see if this item is already claimed; if not, it's ours now
   if not radiant.entities.get_player_id(item) or radiant.entities.get_player_id(item) == '' then
      radiant.entities.set_player_id(item, session.player_id)
   end
   
   local location = radiant.entities.get_world_grid_location(item)
   local root_form, iconic_form = entity_forms_lib.get_forms(item)

   local carrying = radiant.entities.get_carrying(item)
   local items = item:get_component('stonehearth:storage')
   if carrying then
      radiant.entities.drop_carrying_on_ground(item, location)
   end
   if items then
      items:drop_all()
   end

   if location and iconic_form then
      radiant.terrain.remove_entity(item)
      radiant.terrain.place_entity_at_exact_location(iconic_form, location)
      radiant.effects.run_exact_effect(iconic_form, 'stonehearth:effects:fursplosion_effect')

      -- reset health and debuffs
      radiant.entities.reset_health(item, true)

      return true
   end
   return false
end

--- Tell a worker to place the item in the world
function AcePlaceItemCallHandler:place_item_in_world(session, response, item_to_place, location, rotation, normal)
   validator.expect_argument_types({'Entity', 'Point3', 'number', 'Point3'}, item_to_place, location, rotation, normal) --any type for table or userdata

   location = radiant.util.to_point3(location)
   normal = radiant.util.to_point3(normal)

   local item, entity_forms = get_root_entity(item_to_place)
   if not entity_forms then
      response:reject({ error = 'item has no entity_forms component'})
      return
   end

   self:_claim_item_for_player(item, session.player_id)
   entity_forms:place_item_on_ground(location, rotation, normal)

   return true
end

--- Tell a worker to place the item in the world
function AcePlaceItemCallHandler:place_item_on_structure(session, response, item, world_location, rotation, structure_entity, normal, transactional)
   validator.expect_argument_types({'Entity', 'Point3', 'number', 'Entity', 'Point3', 'boolean'}, item, world_location, rotation, structure_entity, normal, transactional)

   world_location = radiant.util.to_point3(world_location)
   local p3_normal = radiant.util.to_point3(normal)

   local item, entity_forms = get_root_entity(item)
   if not entity_forms then
      response:reject({ error = 'item has no entity_forms component'})
   end

   if structure_entity:get_uri() == 'stonehearth:build2:entities:structure' then
      return self:_place_item_on_new_structure(session, response, item, world_location, rotation, structure_entity, p3_normal)
   end

   local location = world_location - radiant.entities.get_world_grid_location(structure_entity)

   -- If object is placed on a done building or a non-building structure, then we need to tell the entity
   -- forms to place it and create the task.
   local building = build_util.get_building_for(structure_entity)
   if not building or building:get_component('stonehearth:construction_progress'):get_finished() then
      self:_claim_item_for_player(item, session.player_id)
      entity_forms:place_item_on_structure(world_location, structure_entity, rotation, p3_normal)
   end

   local ghost = entity_forms:get_ghost_placement_entity()
   if transactional then
      stonehearth.build:add_fixture_command(session, response, structure_entity, item, nil, location, normal, rotation, ghost)
   else
      stonehearth.build:add_fixture(structure_entity, item, nil, location, p3_normal, rotation, ghost)
   end

   return true
end

-- if the item didn't already belong to the player, claim it and add it to inventory
function AcePlaceItemCallHandler:_claim_item_for_player(item, player_id)
   log:debug('considering claiming %s for %s', item, player_id)
   if radiant.entities.get_player_id(item) ~= player_id then
      radiant.entities.set_player_id(item, player_id)
      local inventory = stonehearth.inventory:get_inventory(player_id)
      if inventory then
         log:debug('adding %s to inventory of %s', item, player_id)
         inventory:add_item(item)
      end
   end
end

return AcePlaceItemCallHandler
