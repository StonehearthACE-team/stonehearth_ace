local CrafterInfoService = class()
local log = radiant.log.create_logger('crafter_info_service')

function CrafterInfoService:initialize()
   if not self._sv.crafter_infos then
      self._sv.crafter_infos = {}
   end
   self._material_map = radiant.create_controller('stonehearth_ace:material_map')
   self._material_cache = {}
   self._material_map_loaded = false

   --TODO: add crafter_info for the players at start so there won't be a delay when crafting the first item
   --NOTE: adding a new crafter_info directly after a player joins is the wrong thing to do,
   --      as the information of crafters seem to have not been loaded yet...

   self._kingdom_assigned_listeners = {}

   self._init_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      self._init_listener = nil
      self:_on_init()
   end)
   self._init_listener_2 = radiant.events.listen(radiant, 'stonehearth_ace:player_embarked', function(args)
      self:get_crafter_info(args.player_id)
   end)

   -- radiant.events.listen(radiant, 'radiant:client_joined', function(e)
   --    self:_create_kingdom_listener(e.player_id)
   -- end)
end

function CrafterInfoService:destroy()
   self:_destroy_listeners()
end

function CrafterInfoService:_destroy_listeners()
   for id, listener in pairs(self._kingdom_assigned_listeners) do
      listener:destroy()
      self._kingdom_assigned_listeners[id] = nil
   end

   if self._init_listener then
      self._init_listener:destroy()
      self._init_listener = nil
   end
   if self._init_listener_2 then
      self._init_listener_2:destroy()
      self._init_listener_2 = nil
   end
end

function CrafterInfoService:_on_init()
   self:_ensure_material_map_loaded()
   
   local players = stonehearth.player:get_non_npc_players()
   for player_id, info in pairs(players) do
      if info.kingdom then
         self:get_crafter_info(player_id)
      else
         -- if the player hasn't yet been assigned a kingdom, listen for it
         self:_create_kingdom_listener(player_id)
      end
   end
end

-- TODO: move the material map into the catalog service?
function CrafterInfoService:_ensure_material_map_loaded()
   if self._material_map_loaded then
      return
   end

   self._material_map_loaded = true
   self._material_map:clear()

   -- Store all entities that have materials
   local entity_uris = stonehearth.catalog:get_all_entity_uris()
   for _, full_uri in pairs(entity_uris) do
      local material_tags = stonehearth.catalog:get_catalog_data(full_uri).materials
      if material_tags then
         self._material_map:add(material_tags, full_uri)
      end
   end
end

function CrafterInfoService:get_uris(material_tags)
   -- we'll probably make the same requests a lot, and it doesn't hurt to cache a little
   local result = self._material_cache[material_tags]
   if not result then
      self:_ensure_material_map_loaded()
      result = self._material_map:intersecting_values(material_tags)
      self._material_cache[material_tags] = result
   end
   return result
end

function CrafterInfoService:_create_kingdom_listener(player_id)
   self._kingdom_assigned_listeners[player_id] = radiant.events.listen(radiant, 'radiant:player_kingdom_assigned', function(args)
      if args.player_id == player_id then
         self._kingdom_assigned_listeners[player_id] = nil
         self:get_crafter_info(player_id)
      end
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
