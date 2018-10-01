local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local rng = _radiant.math.get_default_rng()
local DEFAULT_TRIBUTE_VALUE = 50
local DEFAULT_MAX_TRIES = 4
local MAX_DEMAND_COUNT_PER_ITEM = 10
local log = radiant.log.create_logger('shakedown_quest')

local ShakeDown = class()

function ShakeDown:initialize()
   self._sv.ctx = nil
   --self._sv.filler_material = 'stonehearth:resources:wood:oak_log'
   self._sv.max_tries = DEFAULT_MAX_TRIES
   self._sv.tribute_value = DEFAULT_TRIBUTE_VALUE
end

-- TODO (lcai): allow user to specify different default tribute value from json
-- Also, this is duplicated from goblin campaign's shakedown. Need to have that one use this
-- script using alias as well, but the destroy function has issues getting the stonehearth
-- player service when trying to destroy the script. Need to figure that out sometime.
function ShakeDown:create(ctx, info)
   self._sv.ctx = ctx

   local tribute_value = info.initial_tribute_value or DEFAULT_TRIBUTE_VALUE

   if ctx.previous_shakedown_value then
      tribute_value = ctx.previous_shakedown_value * 1.2
   end

   self:_determine_filler_material(ctx.player_id, info.filler_material)

   self._sv.ctx = ctx
   self._sv.tribute_value = tribute_value

   ctx.previous_shakedown_value = tribute_value
end

function ShakeDown:destroy()
   if self._sv.ctx and stonehearth.player then
      stonehearth.player:set_neutral_to_everyone(self._sv.ctx.npc_player_id, false)
   end
end

function ShakeDown:_determine_filler_material(player_id, info_material)
   local biome = stonehearth.world_generation:get_biome_alias()
   local population = stonehearth.population:get_population(player_id)
   local kingdom = population and population:get_kingdom()
   local filler_material = nil

   -- get the filler material from constants if possible
   local gm_consts = stonehearth.constants.game_master
   local filler_materials = gm_consts and gm_consts.quests and gm_consts.quests.filler_materials
   -- first category is biome; check if there's a kingdom override for it
   if filler_materials and filler_materials[biome] then
      if kingdom and filler_materials[biome][kingdom] then
         filler_material = filler_materials[biome][kingdom]
      else
         filler_material = filler_materials[biome].default
      end
      log:error('found biome filler materials: %s', tostring(filler_material))
   end
   -- if biome keys didn't work out, check for a general kingdom setting
   filler_material = filler_material or (kingdom and filler_materials and filler_materials[kingdom]) or (info_material and info_material[biome])

   if filler_material then
      -- if we got an array instead of a single item, pick a random one from the array
      if type(filler_material) == 'table' and next(filler_material) then
         filler_material = filler_material[rng:get_int(1, #filler_material)]
      end

      if radiant.resources.load_json(filler_material) then
         self._sv.filler_material = filler_material
      end
   end
end

-- cache the information for the object we'll use to fill up to
-- the needed tribute value
--
function ShakeDown:_construct()
   local uri = self._sv.filler_material
   self._filler_info = {
      uri = uri,
      worth = self:_get_value_in_gold(uri),
   }
end

--
function ShakeDown:on_transition(transition)
   local ctx = self._sv.ctx

   -- go to war if the player ever fails or opts out
   if transition == 'shakedown_refused' or
      transition == 'collection_failed' then
      stonehearth.player:set_neutral_to_everyone(ctx.npc_player_id, false)
      return
   end
end

-- return a table containing the tribute information needed for the
-- demand tribute encounter
--
function ShakeDown:get_tribute_demand()
   local ctx = self._sv.ctx
   local player_id = ctx.player_id

   local inventory = stonehearth.inventory:get_inventory(player_id)
   if not inventory then
      return
   end

   local items = inventory:get_item_tracker('stonehearth:basic_inventory_tracker')
                              :get_tracking_data()
   local keys = items:get_keys()
   local key_count = #keys

   local tries = 0
   local max_tries = self._sv.max_tries
   local remaining_value = self._sv.tribute_value
   local tribute = {}

   while key_count > 0 and tries < max_tries and remaining_value > 0 do
      local uri = keys[rng:get_int(1, key_count)]
      local _, entity = next(items:get(uri).items)
      if entity then
         if self:_is_requestable(entity) then
            local worth = self:_get_value_in_gold(entity)
            if worth > 0 then
               local cap = math.min((remaining_value / worth) + 1, MAX_DEMAND_COUNT_PER_ITEM)
               local count = rng:get_int(1, cap)
               if not tribute[uri] then
                  local info = items:get(uri)
                  tribute[uri] = {
                     uri = uri,
                     count = 0,
                     icon = info.icon,
                     display_name = info.display_name,
                  }
               end
               tribute[uri].count = tribute[uri].count + count
               remaining_value = remaining_value - (count * worth)
            end
         end
         tries = tries + 1
      end
   end

   -- make up the rest in oak logs
   if remaining_value > 0 then
      if not self._filler_info then
         self:_construct()
      end
      local fi = self._filler_info
      local uri = fi.uri

      local count = radiant.math.round(remaining_value / fi.worth)
      if not tribute[uri] then
         tribute[uri] = {
            uri = uri,
            count = 0,
            icon = fi.icon,
            display_name = fi.display_name,
         }
      end
      tribute[uri].count = tribute[uri].count + count
   end

   -- the price of poker just went up!
   self._sv.tribute_value = self._sv.tribute_value * 1.25;

   return tribute
end

function ShakeDown:_is_requestable(entity)
   --exempt food items, since they may be eaten without the player's approval
   if radiant.entities.is_material(entity, 'food') or radiant.entities.is_material(entity, 'food_container') then
      return false
   end
   --exempt money
   if radiant.entities.is_material(entity, 'gold') or radiant.entities.is_material(entity, 'money') then
      return false
   end
   --exempt non-iconic form items, since it may end up asking for a number of items that are not placed
   local entity_forms_component = entity:get_component('stonehearth:entity_forms')
   local is_iconic = not entity_forms_component or not entity_forms_component:get_iconic_entity()

   --exempt trophies, since it may require items player cannot acquire more of
   if radiant.entities.get_category(entity) == 'trophy' then
      return false
   end

   return is_iconic
end

function ShakeDown:_get_value_in_gold(entity)
   local entity_uri, _ = entity_forms.get_uris(entity)
   local net_worth = radiant.entities.get_net_worth(entity_uri)
   return net_worth or 0
end

return ShakeDown
