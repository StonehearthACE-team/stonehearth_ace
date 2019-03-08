local UnitInfoComponent = require 'stonehearth.components.unit_info.unit_info_component'
local AceUnitInfoComponent = class()
local rng = _radiant.math.get_default_rng()
local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

-- TODO: implement some kind of randomized naming so you can get uniquely named items from regular loot mechanics
-- perhaps limit it to items of higher-than-base quality?
-- would have to delay setting then, since that won't happen immediately on creation
-- could provide for some sort of interesting mechanic whereby "polishing" an item results in higher quality
--    and reveals the uniqueness of the item
AceUnitInfoComponent._ace_old_create = UnitInfoComponent.create
function AceUnitInfoComponent:create()
   self._is_create = true

   local json = radiant.entities.get_json(self) or {}
   if json.display_name then
      self:set_display_name(json.display_name)
   end
   if json.custom_name then
      self:set_custom_name(json.custom_name, json.custom_data)
   end
   if json.description then
      self:set_description(json.description)
   end
   if json.icon then
      self:set_icon(json.icon)
   end
   if json.locked then
      self:lock(type(json.locked) == 'string' and json.locked or ':create()')
   end
   
   if self._ace_old_create then
      self:_ace_old_create()
   end
end

AceUnitInfoComponent._ace_old_activate = UnitInfoComponent.activate
function AceUnitInfoComponent:activate()
   if not self._sv.titles then
      self._sv.titles = {}
   end

   if self._ace_old_activate then
      self:_ace_old_activate()
   end
end

AceUnitInfoComponent._ace_old_post_activate = UnitInfoComponent.post_activate
function AceUnitInfoComponent:post_activate()
   self._player_id_trace = self._entity:trace_player_id('titles')
      :on_changed(
         function ()
            self:_on_player_id_changed()
         end
      )
   
   self:_on_player_id_changed()

   if self._ace_old_post_activate then
      self:_ace_old_post_activate()
   end
end

AceUnitInfoComponent._ace_old_destroy = UnitInfoComponent.destroy
function AceUnitInfoComponent:destroy()
   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end

   if self._ace_old_destroy then
      self:_ace_old_destroy()
   end
end

function AceUnitInfoComponent:_on_player_id_changed()
   local pop = stonehearth.population:get_population(self._entity:get_player_id())
   local titles_json = pop and pop:get_titles_json_for_entity(self._entity)
   if titles_json ~= self._sv.titles_json then
      self._sv.titles_json = titles_json
      self.__saved_variables:mark_changed()
   end
end

-- for now, only change set_custom_name to consider 'locked'
-- since this is the only thing that can be custom-set arbitrarily by the player
-- in future, perhaps extend this capability to set_description and/or set_icon
AceUnitInfoComponent._ace_old_set_custom_name = UnitInfoComponent.set_custom_name
function AceUnitInfoComponent:set_custom_name(custom_name, custom_data, propogate_to_forms)
   if self._sv.locked then
      return false
   end

   -- if we aren't currently using a title, clear the display name
   -- the base function will then assign the default custom name i18n string
   if self._sv.display_name ~= 'i18n(stonehearth_ace:ui.game.entities.custom_name_with_title)' then
      self._sv.display_name = nil
   end
   self:_ace_old_set_custom_name(custom_name, self:_process_custom_data(custom_data))
   if propogate_to_forms ~= false then
      self:_propogate_custom_name(custom_name, custom_data)
   end
   return true
end

function AceUnitInfoComponent:_propogate_custom_name(custom_name, custom_data)
   local root, iconic = entity_forms.get_forms(self._entity)
   for _, form in ipairs({root, iconic}) do
      if form and form ~= self._entity then
         form:add_component('stonehearth:unit_info'):set_custom_name(custom_name, custom_data, false)
      end
   end
end

--[[
function UnitInfoComponent:set_description(custom_description)
   self._sv.description = custom_description
   self:_trigger_on_change()
end

function UnitInfoComponent:set_icon(custom_icon)
   self._sv.icon = custom_icon
   self:_trigger_on_change()
end
]]

function AceUnitInfoComponent:is_notable()
   return self._sv.is_notable or false
end

function AceUnitInfoComponent:set_notability(is_notable)
   self._sv.is_notable = is_notable
   self.__saved_variables:mark_changed()
end

function AceUnitInfoComponent:get_titles()
   return self._sv.titles
end

function AceUnitInfoComponent:has_title(title, rank)
   local title_rank = self._sv.titles[title]
   return title_rank and (not rank or title_rank >= rank)
end

-- once bestowed, a title is never removed; it can only be increased in rank
function AceUnitInfoComponent:add_title(title, rank, propogate_to_forms)
   if not self:has_title(title, rank) then
      self._sv.titles[title] = rank or 1

      -- if this was just a regular entity before, set its custom name to its catalog display name
      if not self._sv.custom_name then
         self._sv.custom_name = self._sv.display_name or stonehearth.catalog:get_catalog_data(self._entity:get_uri()).display_name
      end

      self.__saved_variables:mark_changed()

      self:_select_new_title(title, rank, propogate_to_forms)
      if propogate_to_forms ~= false then
         self:_propogate_title(title, rank)
      end

      return true
   end
end

function AceUnitInfoComponent:_propogate_title(title, rank)
   local root, iconic = entity_forms.get_forms(self._entity)
   for _, form in ipairs({root, iconic}) do
      if form and form ~= self._entity then
         form:add_component('stonehearth:unit_info'):add_title(title, rank, false)
      end
   end
end

function AceUnitInfoComponent:_select_new_title(title, rank, propogate_to_forms)
   if stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'auto_select_new_titles', true) then
      self:select_title(title, rank, propogate_to_forms)
   end
end

function AceUnitInfoComponent:select_title(title, rank, propogate_to_forms)
   -- if no rank is provided, assume the highest rank of that title we have
   if title and self._sv.titles[title] then
      rank = math.min(rank or self._sv.titles[title], self._sv.titles[title])
      local pop = stonehearth.population:get_population(self._entity:get_player_id())
      self._sv.current_title = pop and pop:get_title_rank_data(self._entity, title, rank) or nil
   else
      self._sv.current_title = nil
   end

   if self._sv.current_title then
      self._sv.display_name = 'i18n(stonehearth_ace:ui.game.entities.custom_name_with_title)'
   else
      self._sv.display_name = 'i18n(stonehearth:ui.game.entities.custom_name)'
   end

   self.__saved_variables:mark_changed()

   self:_trigger_on_change()

   if propogate_to_forms ~= false then
      self:_propogate_selected_title(title, rank)
   end
end

function AceUnitInfoComponent:_propogate_selected_title(title, rank)
   local root, iconic = entity_forms.get_forms(self._entity)
   for _, form in ipairs({root, iconic}) do
      if form and form ~= self._entity then
         form:add_component('stonehearth:unit_info'):select_title(title, rank, false)
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

function AceUnitInfoComponent:_process_custom_data(custom_data)
   if not custom_data then
      return
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
end

return AceUnitInfoComponent
