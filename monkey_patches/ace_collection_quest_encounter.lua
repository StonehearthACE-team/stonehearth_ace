local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local Entity = _radiant.om.Entity
local rng = _radiant.math.get_default_rng()

local CollectionQuest = require 'stonehearth.services.server.game_master.controllers.encounters.collection_quest_encounter'
local AceCollectionQuest = class()

AceCollectionQuest._ace_old_restore = CollectionQuest.restore
function AceCollectionQuest:restore()
   self:_ace_old_restore()
   self:_create_quest_storage_listener()
end

AceCollectionQuest._ace_old_destroy = CollectionQuest.__user_destroy
function AceCollectionQuest:destroy()
   self:_ace_old_destroy()
   self:_destroy_quest_storage()
end

function AceCollectionQuest:_destroy_quest_storage()
   if self._quest_storage_listener then
      self._quest_storage_listener:destroy()
      self._quest_storage_listener = nil
   end
   if self._sv._quest_storage then
      self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(false)
      self._sv._quest_storage = nil
   end
end

function AceCollectionQuest:_create_quest_storage_listener()
   if self._sv._quest_storage then
      self._quest_storage_listener = radiant.events.listen(self._sv._quest_storage, 'stonehearth_ace:quest_storage:all_requirements_satisfied', self, self._update_progress)
   end
end

-- called by the ui if the player accepts the terms of the shakedown.
--
AceCollectionQuest._ace_old__on_shakedown_accepted = CollectionQuest._on_shakedown_accepted
function AceCollectionQuest:_on_shakedown_accepted()
   self:_ace_old__on_shakedown_accepted()

   -- try to create a quest storage if gameplay setting allows
   local ctx = self._sv.ctx
   local player_id = ctx.player_id
   local use_quest_storage = self._sv._info.use_quest_storage ~= false
   if stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'use_quest_storage', true) and use_quest_storage then
      local item_requirements = self:_get_item_requirements()
      if #item_requirements < 1 then
         -- no item requirements? no need for quest storage
         return
      end

      self._sv._quest_storage = game_master_lib.create_quest_storage(player_id, self._sv._info.quest_storage_uri, item_requirements, self._sv.bulletin)
      self:_create_quest_storage_listener()
   end
end

function AceCollectionQuest:_get_item_requirements()
   local requirements = {}
   local items = self._sv.demand
   for _, item in pairs(items) do
      table.insert(requirements, {
         uri = item.uri,
         quantity = item.count,
      })
   end

   return requirements
end

function AceCollectionQuest:_on_collection_paid()
   if not self._sv.bulletin then
      return false  -- Protect against spam clicks
   end

   -- take the items!
   local tracking_data = self._player_inventory_tracking_data

   -- first take from quest storage
   local removed = {}
   if self._sv._quest_storage then
      local consumed = self._sv._quest_storage:add_component('stonehearth_ace:quest_storage'):destroy_storage(true)
      -- destroying actually destroys the entity, so clear our reference to it and then destroy our listener
      self._sv._quest_storage = nil
      self:_destroy_quest_storage()

      for _, consumed_data in ipairs(consumed) do
         local uri = consumed_data.requirement.uri
         removed[uri] = (removed[uri] or 0) + consumed_data.num_consumed
      end
   end

   for uri, info in pairs(self._sv.demand) do
      local count = info.count - (removed[uri] or 0)
      if count > 0 and tracking_data:contains(uri) then
         local entities = tracking_data:get(uri).items
         for i = 1, count do
            local id, entity = next(entities)
            if entity then
               radiant.entities.kill_entity(entity)
            end
         end
      end
   end

   --Should put a final bulletin here, as a reward
   local bulletin_data = self._sv._info.nodes.collection_success.bulletin
   bulletin_data.ok_callback = '_on_collection_success_ok'
   self:_update_bulletin(bulletin_data, { view = 'StonehearthCollectionQuestBulletinDialog' })
end

function AceCollectionQuest:_get_stored_item_quantity(quest_storage_status, requirement)
   if quest_storage_status then
      for _, storage in ipairs(quest_storage_status) do
         if requirement.uri == storage.requirement.uri then
            return storage.quantity
         end
      end
   end
end

function AceCollectionQuest:_update_progress()
   assert(self._player_inventory_tracking_data)

   local bulletin = self._sv.bulletin
   if not bulletin then
      return
   end
   local tracking_data = self._player_inventory_tracking_data
   local items = self._sv.demand

   local quest_storage = self._sv._quest_storage
   local item_requirements_status = quest_storage and quest_storage:add_component('stonehearth_ace:quest_storage'):get_requirements_status()

   self._sv.have_enough = true
   for _, item in pairs(items) do
      -- collection quest uses basic_inventory_tracker, which tracks regardless of storage situation
      -- so cached_count is just a separate value not being double-counted in progress
      item.cached_count = self:_get_stored_item_quantity(item_requirements_status, item)
      item.items_cached_class = (item.cached_count == item.count) and 'fullyCached' or 'notFullyCached'
      item.progress = 0
      if tracking_data:contains(item.uri) then
         local info = tracking_data:get(item.uri)
         item.progress = info.count
         if item.progress < item.count then
            self._sv.have_enough = false
         end
      else
         self._sv.have_enough = false
      end
   end
   self.__saved_variables:mark_changed()

   bulletin:mark_data_changed()
end

return AceCollectionQuest
