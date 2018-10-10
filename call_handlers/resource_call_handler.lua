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
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

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
               end)
         end)
      :fail(function(selector)
            response:reject('no region')
         end)
      :go()
end

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
               if command_comp:has_command(command) then
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

   response:resolve(true)
end

function ResourceCallHandler:set_items_auto_harvest(session, response, entities, enabled)
   for _, entity in ipairs(entities) do
      _radiant.call('stonehearth:toggle_auto_harvest', entity, enabled)
   end

   response:resolve(true)
end

return ResourceCallHandler
