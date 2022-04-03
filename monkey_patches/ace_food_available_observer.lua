local FOOD_UNFINDABLE_NOTIFICATION = 'i18n(stonehearth:ui.game.entities.where_is_food_notification)'

local FOOD_CHECK_INTERVAL = 60000
local FOOD_CHECK_RANGE = 20000
local GROUND = 1
local STORAGE = 2

local rng = _radiant.math.get_default_rng()

local AceFoodAvailableObserver = class()

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

return AceFoodAvailableObserver
