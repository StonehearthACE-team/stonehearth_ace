local CrafterInfoService = class()
local log = radiant.log.create_logger('crafter_info_service')

function CrafterInfoService:initialize()
   if not self._sv.crafter_infos then
      self._sv.crafter_infos = {}
   end

   --TODO: add crafter_info for the players at start so there won't be a delay when crafting the first item
   --NOTE: adding a new crafter_info directly after a player joins is the wrong thing to do,
   --      as the information of crafters seem to have not been loaded yet...

   self._kingdom_assigned_listeners = {}

   self._init_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      self._init_listener = nil
      local players = stonehearth.player:get_non_npc_players()
      for player_id, info in pairs(players) do
         if info.kingdom then
            self:get_crafter_info(player_id)
         else
            -- if the player hasn't yet been assigned a kingdom, listen for it
            self:_create_kingdom_listener(player_id)
         end
      end
   end)

   radiant.events.listen(radiant, 'radiant:client_joined', function(e)
      self:_create_kingdom_listener(e.player_id)
   end)
end

function CrafterInfoService:_create_kingdom_listener(player_id)
   self._kingdom_assigned_listeners[player_id] = radiant.events.listen_once(radiant, 'radiant:player_kingdom_assigned', function()
      self._kingdom_assigned_listeners[player_id] = nil
      self:get_crafter_info(player_id)
   end)
end

function CrafterInfoService:add_crafter_info(player_id)
   local crafter_info = radiant.create_controller('stonehearth_ace:crafter_info_controller', player_id)
   self._sv.crafter_infos[player_id] = crafter_info
   self.__saved_variables:mark_changed()
   return crafter_info
end

function CrafterInfoService:get_crafter_info(player_id)
   local crafter_info = self._sv.crafter_infos[player_id]
   if not crafter_info then
      crafter_info = self:add_crafter_info(player_id)
   end
   return crafter_info
end

return CrafterInfoService
