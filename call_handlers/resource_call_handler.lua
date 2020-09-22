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
                     :fail(function(result)
                        response:reject('canceled')
                     end)
               end)
               :fail(function(result)
                  response:reject('no entities')
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
               :fail(function(result)
                  response:reject('no entities')
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

function ResourceCallHandler:box_cancel_placement(session, response)
   stonehearth.selection:select_xz_region('box_cancel_placement')
      :set_max_size(50)
      :require_supported(false)
      :use_outline_marquee(Color4(192, 0, 0, 32), Color4(192, 0, 0, 255))
      :set_cursor('stonehearth:cursors:cancel')
      :allow_unselectable_support_entities(false)
      :done(function(selector, box)
            _radiant.call('stonehearth_ace:box_get_commandable_entities', box, {'stonehearth:commands:destroy_item'}, false)
               :done(function(result)
                  _radiant.call('stonehearth_ace:cancel_placement', result.entities)
                  response:resolve(true)
               end)
               :fail(function(result)
                  response:reject('no entities')
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

function ResourceCallHandler:cancel_placement(session, response, entities)
   for _, entity in ipairs(entities) do
      _radiant.call('stonehearth:destroy_item', entity)
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
         local loot_drops = entity:get_component('stonehearth:loot_drops')
         if loot_drops then
            loot_drops:set_auto_loot_player_id(session.player_id)
         end
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

function ResourceCallHandler:place_buildable_entity(session, response, uri)
   local entity = radiant.entities.create_entity(uri)
   local buildable_data = radiant.entities.get_entity_data(entity, 'stonehearth_ace:buildable_data')
   local requires_terrain = buildable_data.requires_terrain
   local placement_filter_fn
   if buildable_data.placement_filter_script then
      local script = radiant.mods.load_script(buildable_data.placement_filter_script)
      placement_filter_fn = script and script.placement_filter_fn
   end

   stonehearth.selection:deactivate_all_tools()
   
   -- TODO: limit selector to valid building locations
   stonehearth.selection:select_location()
      :set_recheck_filter_on_rotation(buildable_data.recheck_filter_on_rotation)
      :set_cursor_entity(entity)
      :set_filter_fn(function (result, selector)
            local this_entity = result.entity   
            local normal = result.normal:to_int()
            local brick = result.brick

            if not this_entity then
               return stonehearth.selection.FILTER_IGNORE
            end

            local rcs = this_entity:get_component('region_collision_shape')
            local region_collision_type = rcs and rcs:get_region_collision_type()
            if region_collision_type == _radiant.om.RegionCollisionShape.NONE then
               return stonehearth.selection.FILTER_IGNORE
            end

            if normal.y ~= 1 then
               return stonehearth.selection.FILTER_IGNORE
            end

            local kind
            if this_entity:get_id() == radiant._root_entity_id then
               kind = radiant.terrain.get_block_kind_at(brick - normal)
               if requires_terrain and kind == nil then
                  return stonehearth.selection.FILTER_IGNORE
               end
            end

            -- if the entity we're looking at is a child entity of our primary entity, ignore it
            local parent = radiant.entities.get_parent(this_entity)
            if not parent or parent == entity then
               return stonehearth.selection.FILTER_IGNORE
            end

            if placement_filter_fn then
               return placement_filter_fn(selector, entity, this_entity, brick, normal, kind)
            else
               return true
            end
         end)
      :done(function(selector, location, rotation)
            _radiant.call('stonehearth_ace:create_buildable_entity', uri, location, rotation)
            radiant.entities.destroy_entity(entity)
            response:resolve(true)
         end)
      :fail(function(selector)
            selector:destroy()
            response:reject('no location')
         end)
      :always(function()
         end)
      :go()
end

-- server function
-- creates the ghost version of the entity in the world
function ResourceCallHandler:create_buildable_entity(session, response, uri, location, rotation)
   location = radiant.util.to_point3(location)
   local entity = radiant.entities.create_entity(uri, { owner = session.player_id })
   radiant.terrain.place_entity(entity, location, { force_iconic = false })
   radiant.entities.turn_to(entity, rotation)

   local buildable_data = radiant.entities.get_entity_data(entity, 'stonehearth_ace:buildable_data')
   if buildable_data and buildable_data.initialize_script then
      local script = radiant.mods.load_script(buildable_data.initialize_script)
      if script and script.on_initialize then
         script.on_initialize(entity)
      end
   end
end

function ResourceCallHandler:get_all_herbalist_planter_data(session, response)
   response:resolve({data = radiant.resources.load_json('stonehearth_ace:data:herbalist_planter:crops')})
end

function ResourceCallHandler:toggle_vine_harvest_request(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local vine = entity:get_component('stonehearth_ace:vine')
   if vine then
      vine:toggle_group_harvest_request()
   end
end

function ResourceCallHandler:toggle_fish_trap_capture(session, response, entity, enabled)
   validator.expect_argument_types({'Entity'}, entity)

   local fish_trap = entity:get_component('stonehearth_ace:fish_trap')
   if fish_trap then
      fish_trap:set_capture_enabled(enabled)
   end
end

return ResourceCallHandler
