local UnitInfoComponent = require 'stonehearth.components.unit_info.unit_info_component'
local AceUnitInfoComponent = class()
local rng = _radiant.math.get_default_rng()
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local log = radiant.log.create_logger('unit_info_component')
local _default_locked_key = ':create()'

function AceUnitInfoComponent.get_locked_key(json)
   local locked = json.locked
   if locked then
      return type(locked) == 'string' and locked or _default_locked_key
   end
end

-- TODO: implement some kind of randomized naming so you can get uniquely named items from regular loot mechanics
-- perhaps limit it to items of higher-than-base quality?
-- would have to delay setting then, since that won't happen immediately on creation
-- could provide for some sort of interesting mechanic whereby "polishing" an item results in higher quality
--    and reveals the uniqueness of the item
AceUnitInfoComponent._ace_old_create = UnitInfoComponent.create
function AceUnitInfoComponent:create()
   self._is_create = true
   self._sv.title_locked = false

   local json = radiant.entities.get_json(self) or {}
   if json.display_name then
      self:set_display_name(json.display_name)
   end
   if json.custom_name then
      self:set_custom_name(json.custom_name, json.custom_data, nil, true)
   end
   if json.description then
      self:set_description(json.description)
   end
   if json.icon then
      self:set_icon(json.icon)
   end
   if json.locked then
      self:lock(self.get_locked_key(json))
   end
   
   if self._ace_old_create then
      self:_ace_old_create()
   end
end

AceUnitInfoComponent._ace_old_restore = UnitInfoComponent.restore
function AceUnitInfoComponent:restore()
   if self._ace_old_restore then
      self:_ace_old_restore()
   end

   if self._sv.title_locked == nil then
      self._sv.title_locked = true
   end
end

-- for now, only change set_custom_name to consider 'locked'
-- since this is the only thing that can be custom-set arbitrarily by the player
-- in future, perhaps extend this capability to set_description and/or set_icon
AceUnitInfoComponent._ace_old_set_custom_name = UnitInfoComponent.set_custom_name
function AceUnitInfoComponent:set_custom_name(custom_name, custom_data, propogate_to_forms, keep_display_name)
   if self._sv.locked then
      return false
   end

   -- if we aren't currently using a title, clear the display name
   -- the base function will then assign the default custom name i18n string
   if not keep_display_name and self._sv.display_name ~= 'i18n(stonehearth_ace:ui.game.entities.custom_name_with_title)' then
      self._sv.display_name = nil
   end

   local name = self:_select_custom_name(custom_name)
   self:_ace_old_set_custom_name(name, self:_process_custom_data(custom_data, self._sv.custom_data))
   if propogate_to_forms ~= false then
      self:_propogate_custom_name(name, custom_data, keep_display_name)
   end
   return true
end

function AceUnitInfoComponent:_select_custom_name(custom_name)
   if radiant.util.is_table(custom_name) then
      if #custom_name then
         if #custom_name > 0 then
            return custom_name[rng:get_int(1, #custom_name)]
         else
            return ''
         end
      else
         local weighted_set = WeightedSet(rng)

         for name, weight in pairs(custom_name) do
            weighted_set:add(name, weight)
         end
      
         return weighted_set:choose_random()
      end
   end

   return custom_name
end

function AceUnitInfoComponent:_propogate_custom_name(custom_name, custom_data, keep_display_name)
   local root, iconic = entity_forms.get_forms(self._entity)
   for _, form in ipairs({root, iconic}) do
      if form and form ~= self._entity then
         form:add_component('stonehearth:unit_info'):set_custom_name(custom_name, custom_data, false, keep_display_name)
      end
   end
end

function AceUnitInfoComponent:set_description(custom_description, description_data)
   if self._sv.description ~= custom_description or description_data then
      self._sv.description = custom_description
      self._sv.description_data = self:_process_custom_data(description_data, self._sv.description_data)
      self:_trigger_on_change()
   end
end

--[[
function UnitInfoComponent:set_icon(custom_icon)
   self._sv.icon = custom_icon
   self:_trigger_on_change()
end
]]

function AceUnitInfoComponent:get_custom_data()
   return self._sv.custom_data
end

function AceUnitInfoComponent:get_description_data()
   return self._sv.description_data
end

function AceUnitInfoComponent:get_title_locked()
   return self._sv.title_locked
end

function AceUnitInfoComponent:set_title_locked(locked)
   self._sv.title_locked = locked and true or false
   self.__saved_variables:mark_changed()
end

function AceUnitInfoComponent:get_current_title()
   return self._sv.custom_data and self._sv.custom_data.current_title
end

function AceUnitInfoComponent:select_title(title, rank)
   -- only make the change if it's not locked
   if self._sv.title_locked then
      return
   end

   -- if no rank is provided, assume the highest rank of that title we have
   if not self._sv.custom_data then
      self._sv.custom_data = {}
   end

   local titles_comp = self._entity:get_component('stonehearth_ace:titles')
   local max_rank = titles_comp and titles_comp:get_highest_rank(title)
   if title and max_rank then
      rank = math.min(rank or max_rank, max_rank)
      local pop = stonehearth.population:get_population(self._entity:get_player_id())
      self._sv.custom_data.current_title = pop and pop:get_title_rank_data(self._entity, title, rank) or nil
   else
      self._sv.custom_data.current_title = nil
   end

   if self._sv.custom_data.current_title then
      self._sv.display_name = 'i18n(stonehearth_ace:ui.game.entities.custom_name_with_title)'
   else
      self._sv.display_name = 'i18n(stonehearth:ui.game.entities.custom_name)'
   end
   
   self.__saved_variables:mark_changed()

   self:_trigger_on_change()
end

function AceUnitInfoComponent:ensure_custom_name()
   -- if this was just a regular entity before, set its custom name to its catalog display name
   if not self._sv.custom_name then
      local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
      if catalog_data then
         self._sv.custom_name = self._sv.display_name or catalog_data.display_name
         self.__saved_variables:mark_changed()
      else
         log:error('%s is missing catalog data', self._entity)
         self._sv.custom_name = 'i18n(stonehearth_ace:ui.game.entities.missing_catalog_data)'
         self.__saved_variables:mark_changed()
      end
   end
end

function AceUnitInfoComponent:is_locked()
   return self._sv.locked
end

function AceUnitInfoComponent:get_locker()
   return self._sv.locker
end

-- locker can be anything: string, table, entity, whatever; most likely a string though
function AceUnitInfoComponent:lock(locker)
   if self._sv.locked then
      -- if it's already locked, it can't be locked
      return false
   end

   self._sv.locked = true
   self._sv.locker = locker
   self.__saved_variables:mark_changed()
   return true
end

-- check if the unlocker can unlock it (default equality comparison unless otherwise specified)
function AceUnitInfoComponent:unlock(unlocker, can_unlock_fn)
   if (can_unlock_fn and can_unlock_fn(self._entity, self._sv.locker, unlocker))
         or (not can_unlock_fn and (not self._sv.locker or self._sv.locker == unlocker)) then
      self:force_unlock()
      return true
   end

   return false
end

function AceUnitInfoComponent:force_unlock()
   self._sv.locked = false
   self._sv.locker = nil
   self.__saved_variables:mark_changed()
end

function AceUnitInfoComponent:_process_custom_data(custom_data, default)
   if not custom_data then
      return default or {}
   end

   if type(custom_data) ~= 'table' then
      return custom_data
   end

   local data = {}
   for k, v in pairs(custom_data) do
      if type(v) ~= 'table' then
         data[k] = v
      else
         if v.type == 'one_of' and type(v.items) == 'table' then
            local index = rng:get_int(1, #v.items)
            data[k] = self:_process_custom_data(v.items[index])
         else
            data[k] = v
         end
      end
   end

   return data
end

return AceUnitInfoComponent
