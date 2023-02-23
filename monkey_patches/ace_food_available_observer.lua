-- ACE: implemented smart storage filter caching and notification gameplay setting

local FOOD_UNFINDABLE_NOTIFICATION = 'i18n(stonehearth:ui.game.entities.where_is_food_notification)'
local EatingLib = require 'stonehearth.ai.lib.eating_lib'

local FOOD_CHECK_INTERVAL = 60000
local FOOD_CHECK_RANGE = 20000
local GROUND = 1
local STORAGE = 2

local rng = _radiant.math.get_default_rng()

local AceFoodAvailableObserver = class()

local function make_storage_filter_fn(args_filter_fn)
   return function(entity)
         local storage = entity:get('stonehearth:storage')
         if not storage then
            return false
         end

         -- Don't look in stockpiles.  Ground searching is done separately.
         if entity:get('stonehearth:stockpile') then
            return false
         end

         -- Don't take items out of non-public storage (e.g.hearthling backpacks)
         if not storage:is_public() then
            return false
         end

         return storage:storage_contains_filter_fn(args_filter_fn)
      end
end

function AceFoodAvailableObserver:_set_failure(kind)
   self._failures[kind] = true

   if self._failures[GROUND] and self._failures[STORAGE] then
      local population = stonehearth.population:get_population(self._entity)
      if population then
         if stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'show_food_unfindable_notification', true) then
            local options = {
               ignore_on_repeat_add = false
            }
            population:show_notification_for_citizen(self._entity, FOOD_UNFINDABLE_NOTIFICATION, options)
         end
      end
   end
end

function AceFoodAvailableObserver:_wakeup()
   if self._looking_timeout then
      self._looking_timeout:destroy()
      self._looking_timeout = nil
   end
   -- Still haven't found food, so check: is there any reachable food?

   local food_filter_fn = EatingLib.make_food_filter()

   local player_id = radiant.entities.get_player_id(self._entity)
   local location = radiant.entities.get_world_grid_location(self._entity)


   -- Look everywhere on the ground.
   local ground_exhausted_cb = function()
      self:_set_failure(GROUND)
   end
   local ground_found_cb = function(item, flush)
      self:_reset_timer()
      return true
   end
   self._ground_if = self._entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
         location,
         food_filter_fn,
         ground_found_cb,
         {
            description = 'food available ground',
            owner_player_id = player_id,
            exhausted_cb = ground_exhausted_cb,
         })

   -- Look everywhere in accessible storage.
   local storage_exhausted_cb = function()
      self:_set_failure(STORAGE)
   end
   local storage_found_cb = function(storage)
      self:_reset_timer()
      return true
   end
   local storage_filter_fn = stonehearth.ai:filter_from_key('stonehearth:find_reachable_entity_type_anywhere',
                                                            food_filter_fn, make_storage_filter_fn(food_filter_fn))
   self._storage_if = self._entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
         location,
         storage_filter_fn,
         storage_found_cb,
         {
            description = 'food available storage',
            owner_player_id = player_id,
            exhausted_cb = storage_exhausted_cb,
         })
end

return AceFoodAvailableObserver
