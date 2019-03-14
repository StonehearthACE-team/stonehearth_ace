--[[
   just replaced the priority with a range to stop stupid log spam
   unfortunately have to override the whole file because it's a compound action so can't monkey-patch it (I think?)
]]

local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

-- TODO: Ideally, this would be refactored to share almost everything with place_item_type_on_structure_action.lua.
local PlaceSummonStoneTypeAction = radiant.class()

PlaceSummonStoneTypeAction.name = 'place summon stone (type)'
PlaceSummonStoneTypeAction.does = 'stonehearth:place_item_type_on_structure'
PlaceSummonStoneTypeAction.args = {
   iconic_uri = 'string',
   quality = 'number'  -- ignored
}
PlaceSummonStoneTypeAction.priority = {0, 1}

local function _is_placeable_iconic(player_id, iconic_uri, item)
   if not item or not item:is_valid() then
      return false
   end
   if item:get_uri() ~= iconic_uri then
      return false
   end
   if player_id ~= radiant.entities.get_player_id(item) then
      return false
   end
   local root_form = entity_forms.get_root_entity(item)
   if not root_form then
      return false
   end
   local being_placed = root_form:get_component('stonehearth:entity_forms'):is_being_placed()
   if being_placed then
      return false
   end

   local placement_data = radiant.entities.get_entity_data(root_form, 'stonehearth:placement')
   if not (placement_data and placement_data.tag == 'summon_stone') then
      return false
   end
   
   return true
end

local function _is_ghost_for_iconic(player_id, iconic_uri, possible_ghost)
   if not possible_ghost or not possible_ghost:is_valid() then
      return false
   end

   if radiant.entities.get_player_id(possible_ghost) ~= player_id then
      return false
   end

   local ghost_form_component = possible_ghost:get_component('stonehearth:ghost_form')
   if not ghost_form_component then
      return false
   end

   if ghost_form_component:get_iconic_uri() ~= iconic_uri then
      return false
   end

   if not ghost_form_component:is_place_item_type() then
      return false
   end
   
   return true
end

function PlaceSummonStoneTypeAction:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local iconic_uri = args.iconic_uri

   local filter_fns = {}
   filter_fns.pickup_filter = stonehearth.ai:filter_from_key('place_summon_stone_type', work_player_id .. ':' .. iconic_uri .. ':p', function(item)
         return _is_placeable_iconic(work_player_id, iconic_uri, item)
      end)
   filter_fns.ghost_filter = stonehearth.ai:filter_from_key('place_summon_stone_type', work_player_id .. ':' .. iconic_uri .. ':g', function(ghost)
         return _is_ghost_for_iconic(work_player_id, iconic_uri, ghost)
      end)

   ai:set_think_output({
      pickup_filter = filter_fns.pickup_filter,
      ghost_filter = filter_fns.ghost_filter,
      owner_player_id = work_player_id,
   })
end

function PlaceSummonStoneTypeAction:start(ai, entity, args)
   ai:set_status_text_key('stonehearth:ai.actions.status_text.place_item_on_structure', { target = ai.CURRENT.carrying })
end

local ai = stonehearth.ai
return ai:create_compound_action(PlaceSummonStoneTypeAction)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:pickup_item_type', {
               filter_fn = ai.BACK(2).pickup_filter,
               description = 'pickup placeable iconic for ghost',
               owner_player_id = ai.BACK(2).owner_player_id,
            })
         :execute('stonehearth:goto_entity_type', {
               filter_fn = ai.BACK(3).ghost_filter,
               description = 'find ghost for iconic',
             })
         :execute('stonehearth:reserve_entity', {
               entity = ai.PREV.destination_entity,
            })
         :execute('stonehearth:place_carrying_on_structure_adjacent', {
               ghost = ai.BACK(2).destination_entity,
            })
