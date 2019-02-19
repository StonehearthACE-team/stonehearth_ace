local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Color4 = _radiant.csg.Color4
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local validator = radiant.validator

local ResourceCallHandler = class()

local boxed_entities = {}

function ResourceCallHandler:box_move(session, response)
   stonehearth.selection:select_xz_region('box_move')
      :set_max_size(50)
      :require_supported(false)
      :use_outline_marquee(Color4(0, 255, 0, 32), Color4(0, 255, 0, 255))
      :set_cursor('stonehearth:cursors:move_cursor')
      :allow_unselectable_support_entities(true)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:box_get_commandable_entities', box, {'stonehearth:commands:move_item'}, true)
               :done(function(result)
                  boxed_entities = result.entities
                  _radiant.call('stonehearth_ace:move_item', 1)
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

function ResourceCallHandler:box_undeploy(session, response)
   stonehearth.selection:select_xz_region('box_undeploy')
      :set_max_size(50)
      :require_supported(false)
      :use_outline_marquee(Color4(255, 0, 0, 32), Color4(255, 0, 0, 255))
      :set_cursor('stonehearth:cursors:move_cursor')
      :allow_unselectable_support_entities(true)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:box_get_commandable_entities', box, {'stonehearth:commands:undeploy_item'}, true)
               :done(function(result)
                  _radiant.call('stonehearth_ace:undeploy_items', result.entities)
                  response:resolve(true)
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

--[[
function ResourceCallHandler:box_enable_auto_harvest(session, response)
   stonehearth.selection:select_xz_region('box_undeploy')
      :set_max_size(50)
      :require_supported(false)
      :use_outline_marquee(Color4(72, 255, 96, 32), Color4(72, 255, 96, 255))
      :set_cursor('stonehearth:cursors:move_cursor')
      :allow_unselectable_support_entities(true)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:box_get_commandable_entities', box, 
               {'stonehearth_ace:commands:enable_auto_harvest', 'stonehearth_ace:commands:disable_auto_harvest'}, false)
               :done(function(result)
                  _radiant.call('stonehearth_ace:set_items_auto_harvest', result.entities, true)
                  response:resolve(true)
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

function ResourceCallHandler:box_disable_auto_harvest(session, response)
   stonehearth.selection:select_xz_region('box_undeploy')
      :set_max_size(50)
      :require_supported(false)
      :use_outline_marquee(Color4(255, 96, 72, 32), Color4(255, 96, 72, 255))
      :set_cursor('stonehearth:cursors:move_cursor')
      :allow_unselectable_support_entities(true)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:box_get_commandable_entities', box,
               {'stonehearth_ace:commands:enable_auto_harvest', 'stonehearth_ace:commands:disable_auto_harvest'}, false)
               :done(function(result)
                  _radiant.call('stonehearth_ace:set_items_auto_harvest', result.entities, false)
                  response:resolve(true)
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end
]]

function ResourceCallHandler:box_get_commandable_entities(session, response, box, commands, allow_neutral_player_ids)
   validator.expect_argument_types({'Cube3', 'table'}, box, commands)

   local cube = Cube3(Point3(box.min.x, box.min.y, box.min.z),
                      Point3(box.max.x, box.max.y, box.max.z))

   local entities = radiant.terrain.get_entities_in_cube(cube)

   local tbl = {}
   for _, entity in pairs(entities) do
      local player_id = entity:get_player_id()
      if player_id == session.player_id or (allow_neutral_player_ids and player_id == '') then
         if not next(commands) then
            table.insert(tbl, entity)
            break
         end

         local command_comp = entity:get_component('stonehearth:commands')

         if command_comp then
            for _, command in pairs(commands) do
               if command_comp:is_command_enabled(command) then
                  table.insert(tbl, entity)
                  break
               end
            end
         end
      end
   end

   response:resolve({entities = tbl})
end

function ResourceCallHandler:move_item(session, response, index)
   local entity = boxed_entities[index]

   if entity then
      _radiant.call('stonehearth:choose_place_item_location', entity)
         :done(function(result)
            _radiant.call('stonehearth_ace:move_item', index + 1)
         end)
         :fail(function(result)
            response:reject('move_item failed')
         end)
   else
      response:resolve(true)
   end
end

function ResourceCallHandler:undeploy_items(session, response, entities)
   for _, entity in ipairs(entities) do
      _radiant.call('stonehearth:undeploy_item', entity)
   end
end

--[[
function ResourceCallHandler:set_items_auto_harvest(session, response, entities, enabled)
   for _, entity in ipairs(entities) do
      _radiant.call('stonehearth_ace:toggle_auto_harvest', entity, enabled)
   end
end
]]

-- as far as I can tell, there isn't a good way to make use of call handler code in other mods
-- so we just copy the base game code here and make our small changes for the replanting option
function ResourceCallHandler:box_harvest_and_replant_resources(session, response)
   stonehearth.selection:select_xz_region(stonehearth.constants.xz_region_reasons.BOX_HARVEST_RESOURCES)
      :set_max_size(50)
      :require_supported(true)
      :use_outline_marquee(Color4(0, 255, 0, 32), Color4(0, 255, 0, 255))
      :set_cursor('stonehearth:cursors:harvest')
      -- Allow selection on buildings/other items that aren't selectable
      :allow_unselectable_support_entities(true)
      :set_find_support_filter(function(result)
            if self:_is_ground(result.entity) then
               return true
            end
            return stonehearth.selection.FILTER_IGNORE
         end)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:server_box_harvest_and_replant_resources', box)
            response:resolve(true)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

function ResourceCallHandler:server_box_harvest_and_replant_resources(session, response, box)
   validator.expect_argument_types({'Cube3'}, box)

   local cube = Cube3(Point3(box.min.x, box.min.y, box.min.z),
                      Point3(box.max.x, box.max.y, box.max.z))

   local entities = radiant.terrain.get_entities_in_cube(cube)

   for _, entity in pairs(entities) do
      self:harvest_entity(session, response, entity, true) -- true for from harvest tool
   end
end

--Call this one if you want to harvest as renewably as possible
function ResourceCallHandler:harvest_entity(session, response, entity, from_harvest_tool)
   validator.expect_argument_types({'Entity', validator.optional('boolean')}, entity, from_harvest_tool)   

   local town = stonehearth.town:get_town(session.player_id)

   local renewable_resource_node = entity:get_component('stonehearth:renewable_resource_node')
   local resource_node = entity:get_component('stonehearth:resource_node')

   if renewable_resource_node and renewable_resource_node:get_harvest_overlay_effect() and renewable_resource_node:is_harvestable() then
      renewable_resource_node:request_harvest(session.player_id)
   elseif resource_node then
      -- check that entity can be harvested using the harvest tool
      if not from_harvest_tool or resource_node:is_harvestable_by_harvest_tool() then
         resource_node:request_harvest(session.player_id, true)   -- Paul: this is the only real change
      end
   end
end

function ResourceCallHandler:box_hunt(session, response)
   stonehearth.selection:select_xz_region(stonehearth.constants.xz_region_reasons.BOX_HARVEST_RESOURCES)
      :set_max_size(50)
      :require_supported(true)
      :use_outline_marquee(Color4(0, 255, 0, 32), Color4(0, 255, 0, 255))
      :set_cursor('stonehearth:cursors:harvest')
      -- Allow selection on buildings/other items that aren't selectable
      :allow_unselectable_support_entities(true)
      :set_find_support_filter(function(result)
            if self:_is_ground(result.entity) then
               return true
            end
            return stonehearth.selection.FILTER_IGNORE
         end)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:server_box_hunt', box)
            response:resolve(true)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

function ResourceCallHandler:server_box_hunt(session, response, box)
   validator.expect_argument_types({'Cube3'}, box)

   local cube = Cube3(Point3(box.min.x, box.min.y, box.min.z),
                      Point3(box.max.x, box.max.y, box.max.z))

   local entities = radiant.terrain.get_entities_in_cube(cube)

   for _, entity in pairs(entities) do
      self:hunt_entity(session, response, entity, true) -- true for from harvest tool
   end
end

local HUNT_ACTION = 'stonehearth_ace:hunt_animal'
function ResourceCallHandler:hunt_entity(session, response, entity, from_harvest_tool)
   validator.expect_argument_types({'Entity', validator.optional('boolean')}, entity, from_harvest_tool)   

   local town = stonehearth.town:get_town(session.player_id)

   local is_animal = radiant.entities.get_player_id(entity) == 'animals'
   if not is_animal then
      return false
   end

   local task_tracker_component = entity:add_component('stonehearth:task_tracker')
   if task_tracker_component:is_activity_requested(HUNT_ACTION) then
      return false -- If someone has requested to hunt already
   end

   local success = task_tracker_component:request_task(session.player_id, 'hunt', HUNT_ACTION, 'stonehearth:effects:attack_indicator_effect')
   return success
end

-- returns true if the entity should be considered a target when box selecting items
function ResourceCallHandler:_is_ground(entity)
   if entity:get_component('terrain') then
      return true
   end
   
   if (entity:get_component('stonehearth:construction_data') or
       entity:get_component('stonehearth:build2:structure')) then
      return true
   end

   return false
end

return ResourceCallHandler
