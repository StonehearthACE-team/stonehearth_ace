local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local Point3 = _radiant.csg.Point3

local Mission = class()

local VERSIONS = {
   ZERO = 0,
   UPGRADE_TO_PARTY_ENTITY = 1, -- If we have a party, we should save off the party entity instead of the party component.
   MULTIPLAYER = 2 -- We need to listen for combat on all non-npc player factions and notify everyone when combat starts
}

function Mission:get_version()
   return VERSIONS.MULTIPLAYER
end

function Mission:initialize()
   self._sv.sighted_bulletin_data = nil
   self._sv.tracking_bulletin_data = nil
   self._sv.ctx = nil
   self._sv.info = nil
   self._sv.party = nil
   self._sv.sighted_bulletins = nil
   self._sv.tracking_bulletin = nil
end

function Mission:activate()
   if self._sv.sighted_bulletin_data or self._sv.tracking_bulletin_data then
      self:_destroy_bulletins()
   end

   if self._sv.sighted_bulletin_data then
      self:_listen_for_sighted()
   end

   if self._sv.tracking_bulletin_data then
      self:_create_tracking_bulletin()
   end
end

function Mission:can_start(ctx, info)
   return true
end

function Mission:start(ctx, info)
   self._sv.ctx = ctx
   self._sv.info = info

   if info.npc_player_id then
      ctx.npc_player_id = info.npc_player_id
   end

   self._sv.party = self:_create_party(ctx, info)

   local bulletin_info = info.sighted_bulletin or info.combat_bulletin
   local tracking_bulletin_info = info.tracking_bulletin

   if bulletin_info then
      self._sv.sighted_bulletin_data = bulletin_info
      self.__saved_variables:mark_changed()
      self:_listen_for_sighted()
   end

   if tracking_bulletin_info then
      self._sv.tracking_bulletin_data = tracking_bulletin_info
      self.__saved_variables:mark_changed()
      self:_create_tracking_bulletin()
   end
end

function Mission:stop()
   self:_destroy_bulletins()

   if self._sighted_listeners then
      self:_destroy_sighted_listeners()
   end
   if self._amenity_trace then
      self._amenity_trace:destroy()
      self._amenity_trace = nil
   end
end

-- Note: Party stays in the world on destroy
function Mission:destroy()
   self:stop()
end

function Mission:_destroy_sighted_listeners()
   for player_id, listener in pairs(self._sighted_listeners) do
      listener:destroy()
   end

   self._sighted_listeners = nil
end

function Mission:_listen_for_sighted()
   local ctx = self._sv.ctx
   local info = self._sv.info
   if not ctx.npc_player_id then
      ctx.npc_player_id = info.npc_player_id
   end
   assert(ctx.npc_player_id, 'no npc_player_id specified for %s', tostring(ctx.encounter_name))

   self._sighted_listeners = {}

   local non_npc_players = stonehearth.player:get_non_npc_players()
   for player_id, player_info in pairs(non_npc_players) do
      if not stonehearth.player:are_player_ids_hostile(ctx.npc_player_id, player_id) then
         return -- don't listen for sighted if players are neutral/friendly
      end

      local population = stonehearth.population:get_population(player_id)
      if population then
         local event = 'stonehearth:population:new_threat' -- default
          if info.combat_bulletin then
            event = 'stonehearth:population:engaged_in_combat'
         end
         self._sighted_listeners[player_id] = radiant.events.listen(population, event, self, self._on_player_new_threat)
      end
   end
end

function Mission:get_party()
   local party = self._sv.party
   if party and party:is_valid() then
      return party
   end
end

-- Returns the party as a party component
function Mission:get_party_component()
   local party = self:get_party()
   return party and party:get_component('stonehearth:party')
end

function Mission:_on_player_new_threat(evt)
   local party = self:get_party_component()
   if party and not self._sv.sighted_bulletins then
      local members = party:get_members()
      local member = members and members[evt.entity_id]
      if member then
         self:_create_sighted_bulletins(member.entity)
         if self._sighted_listeners then
            self:_destroy_sighted_listeners()
         end
      end
   end
end

function Mission:_create_sighted_bulletins(party_member)
   if not self._sv.sighted_bulletins then
      self._sv.sighted_bulletins = {}
      local bulletin_data = self._sv.sighted_bulletin_data

      local non_npc_players = stonehearth.player:get_non_npc_players()
      if not self._sv.info.only_notify_owner then
         for player_id, player_info in pairs(non_npc_players) do
            self._sv.sighted_bulletins[player_id] = game_master_lib.create_zoom_bulletin(party_member, player_id, bulletin_data)
         end
      else
         self._sv.sighted_bulletins[self._sv.ctx.player_id] = game_master_lib.create_zoom_bulletin(party_member, self._sv.ctx.player_id, bulletin_data)
      end
      self.__saved_variables:mark_changed()
   end
end

function Mission:_create_tracking_bulletin()
   if not self._sv.tracking_bulletin then
      local bulletin_data = self._sv.tracking_bulletin_data
      if bulletin_data then
         local party = self:get_party_component()
         local members = party and party:get_members()
         if members then
            for i, member in pairs(members) do
               if member and member.entity and member.entity:is_valid() then     
                  self._sv.tracking_bulletin = game_master_lib.create_tracking_bulletin(member.entity, self._sv.ctx.player_id, bulletin_data)
                  self._sv.tracking_bulletin:_listen_for_target_entity_destruction()
                  self.__saved_variables:mark_changed()
                  break
               end
            end
         end
      end
   end
end

function Mission:_create_party(ctx, info)
   assert(ctx)
   radiant.assert(ctx.enemy_location, "no enemy location for mission %s", radiant.util.table_tostring(info))
   radiant.assert(info.offset, "no offset for mission %s", radiant.util.table_tostring(info))
   radiant.assert(info.members, "no members for mission %s", radiant.util.table_tostring(info))

   assert(ctx.npc_player_id)

   -- allow mission to override enemy location if specified
      -- used to place new party where the previous (wait) encounter's entity was
      -- example: wait event on enemy destroyed, use the source location to place a new
      -- monster where the old one was destroyed
   if info.use_wait_entity_location then
      ctx.enemy_location = ctx.source_location
   end

   local origin = ctx.enemy_location

   local population = stonehearth.population:get_population(ctx.npc_player_id)

   local offset = Point3(info.offset.x, info.offset.y, info.offset.z)

   -- xxx: "enemy" here should be "npc"
   local party_entity = stonehearth.unit_control:get_controller(ctx.npc_player_id):create_party()
   local party_component = party_entity:get_component('stonehearth:party')

   local raid_timeout_minutes = info.raid_timeout_minutes or 4300 -- ~ 3 days
   local raid_timeout_variance_minutes = info.raid_timeout_variance_minutes or 0

   --Stick all the citizens into a table sorted by type, and add them to the party
   local citizens_by_type = {}
   if info.members then
      for type, info in pairs(info.members) do
         local members = game_master_lib.create_citizens(population, info, origin + offset, ctx)
         citizens_by_type[type] = members
         for i, member in ipairs(members) do
            -- All raids timeout after a certain number of minutes
            radiant.entities.set_attribute(member, 'raid_timeout_minutes', raid_timeout_minutes)
            radiant.entities.set_attribute(member, 'raid_timeout_variance_minutes', raid_timeout_variance_minutes)
            party_component:add_member(member)
         end
      end
      -- if the user cares, register all the citizens
      if info.ctx_entity_registration_path then
         game_master_lib.register_entities(ctx, info.ctx_entity_registration_path, citizens_by_type)
      end
   end

   return party_entity
end

function Mission:_find_closest_stockpile(origin, player_id)
   assert(origin)
   assert(player_id)

   local inventory = stonehearth.inventory:get_inventory(player_id)
   if not inventory then
      return nil
   end
   local stockpiles = inventory:get_all_stockpiles()
   if not stockpiles then
      return nil
   end

   local best_dist, best_stockpile
   for id, stockpile in pairs(stockpiles) do
      local location = radiant.entities.get_world_grid_location(stockpile)
      local sc = stockpile:get_component('stonehearth:stockpile')
      local items = sc:get_items()
      if next(items) then
         local cube = sc:get_bounds()
         local dist = cube:distance_to(origin)
         if not best_dist or dist < best_dist then
            best_dist = dist
            best_stockpile = stockpile
         end
      end
   end

   return best_stockpile
end

-- Create a trace that calls the callback when enemy amenity changes
function Mission:create_amenity_trace(callback_fn)
   local ctx = self._sv.ctx
   if ctx and callback_fn then
      local pop = stonehearth.population:get_population(ctx.npc_player_id)
      if pop then
         self._amenity_trace = radiant.events.listen(pop, 'stonehearth:amenity_changed', callback_fn)
      end
   end
end

-- Called by individual missions when amenity changes
function Mission:suppress_enemy_notification()
   local ctx = self._sv.ctx
   if not stonehearth.player:are_player_ids_hostile(ctx.npc_player_id, ctx.player_id) then
      -- if players no longer hostile, make sure enemy notification does not appear
      if self._sighted_listeners then
         self:_destroy_sighted_listeners()
      end
      self:_destroy_bulletins()
   else
      -- if they become hostile again, listen for enemy no
      if not self._sighted_listeners then
         self:_listen_for_sighted()
      end
   end
end

function Mission:_destroy_bulletins()
   if self._sv.sighted_bulletins then
      for player_id, bulletin in pairs(self._sv.sighted_bulletins) do
         stonehearth.bulletin_board:remove_bulletin(bulletin)
      end
      self._sv.sighted_bulletins = nil
   end

   if self._sv.tracking_bulletin then
      stonehearth.bulletin_board:remove_bulletin(self._sv.tracking_bulletin)
      self._sv.tracking_bulletin = nil
   end
   
   self.__saved_variables:mark_changed()
end

function Mission:fixup_post_load(old_save_data)
   if old_save_data.version < VERSIONS.UPGRADE_TO_PARTY_ENTITY then
      self._sv.party = nil
      local party_component = old_save_data.party
      if party_component then
         local entity = party_component._entity
         if entity and entity:is_valid() then
            self._sv.party = entity
         end
      end
   end

   if old_save_data.version < VERSIONS.MULTIPLAYER then
      if old_save_data.sighted_bulletin then
         self._sv.sighted_bulletins = {}
         self._sv.sighted_bulletins[self._sv.ctx.player_id or 'player_1'] = old_save_data.sighted_bulletin
      end
   end
end

return Mission

