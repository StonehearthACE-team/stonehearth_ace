local PlayerPatrolBanners = class()

function PlayerPatrolBanners:initialize()
   self._sv.banners_by_party = {}
   self._sv.ordered_banners_by_party = {}
   self._sv.party_ids_by_banner = {}
   self._sv.outdated_parties = {}
   self._sv.patrol_banners = {}
end

function PlayerPatrolBanners:create(player_id)
   self._sv.player_id = player_id
end

function PlayerPatrolBanners:activate()
   self._banner_listeners = {}
   for _, banners in pairs(self._sv.banners_by_party) do
      for id, banner in pairs(banners) do
         self:_add_banner_listeners(id, banner:get_object())
      end
   end
end

function PlayerPatrolBanners:destroy()
   for _, banners in pairs(self._sv.banners_by_party) do
      for id, _ in pairs(banners) do
         self:_destroy_banner_listeners(id)
      end
   end
end

function PlayerPatrolBanners:_add_banner_listeners(id, banner_object)
   self:_destroy_banner_listeners(id)
   local listeners = {}

   table.insert(listeners, radiant.events.listen(banner_object, 'stonehearth_ace:patrol_banner:sequence_changed', self, self._on_banner_sequence_changed))
   
   self._banner_listeners[id] = listeners
end

function PlayerPatrolBanners:_destroy_banner_listeners(id)
   local listeners = self._banner_listeners[id]

   if listeners then
      for _, listener in ipairs(listeners) do
         listener:destroy()
      end
      self._banner_listeners[id] = nil
   end
end

function PlayerPatrolBanners:_get_party_id(banner)
   return self._sv.party_ids_by_banner[banner:get_id()]
end

function PlayerPatrolBanners:_on_banner_sequence_changed(banner_object)
   local party_id = self:_get_party_id(banner_object)
   if party_id then
      self._sv.outdated_parties[party_id] = true
      self.__saved_variables:mark_changed()
   end
end

function PlayerPatrolBanners:get_banners_by_party(party_id)
   local banners = self._sv.banners_by_party[party_id]
   if not banners then
      banners = {}
      self._sv.banners_by_party[party_id] = banners
      self.__saved_variables:mark_changed()
   end
   return banners
end

function PlayerPatrolBanners:get_ordered_banners_by_party(party_id)
   local banners = self._sv.ordered_banners_by_party[party_id]
   if not banners or self._sv.outdated_parties[party_id] then
      banners = self:_order_party_banners(party_id)
   end
   return banners
end

function PlayerPatrolBanners:update_ordered_party_banners(party_id)
   -- if party_id isn't specified, update all
   for id, _ in pairs(self._sv.outdated_parties) do
      if not party_id or party_id == id then
         self:_order_party_banners(id)
      end
   end
end

function PlayerPatrolBanners:_order_party_banners(party_id)
   local banners = self:get_banners_by_party(party_id)
   local ordered_banners = {}
   local checks = {}

   -- just start with the first banner and follow next_banner to get the order
   for id, banner in pairs(banners) do
      local pb = banner:get_object() and banner:get_banner()
      if not pb then
         banners[id] = nil
      elseif not next(checks) then
         while not checks[id] do
            checks[id] = true
            table.insert(ordered_banners, banner)
            local next = pb:get_next_banner()
            if next then
               id = next:get_id()
               banner = banners[id]
               if banner then
                  pb = banner:get_object() and banner:get_banner()
               else
                  break
               end
            else
               break
            end
         end
      end
   end

   self._sv.outdated_parties[party_id] = false
   self._sv.ordered_banners_by_party[party_id] = ordered_banners
   self.__saved_variables:mark_changed()

   return ordered_banners
end

function PlayerPatrolBanners:add_banner(banner)
   if banner:get_object():get_player_id() ~= self._sv.player_id then
      return
   end

   local pb_comp = banner:get_banner()
   local party_id = pb_comp and pb_comp:get_party()
   if party_id then
      local banners = self:get_banners_by_party(party_id)
      local banner_id = banner:get_id()
      banners[banner_id] = banner
      self._sv.patrol_banners[banner_id] = banner:get_object()
      self._sv.party_ids_by_banner[banner_id] = party_id
      self._sv.outdated_parties[party_id] = true
      self:update_ordered_party_banners(party_id)

      self:_add_banner_listeners(banner_id, banner:get_object())
   end
end

function PlayerPatrolBanners:remove_banner(banner_id)
   local party_id = self._sv.party_ids_by_banner[banner_id]

   if party_id then
      local banners = self:get_banners_by_party(party_id)
      banners[banner_id] = nil
      self._sv.patrol_banners[banner_id] = nil
      self._sv.party_ids_by_banner[banner_id] = nil
      self._sv.outdated_parties[party_id] = true
      self:update_ordered_party_banners(party_id)

      self:_destroy_banner_listeners(banner_id)
   end
end

return PlayerPatrolBanners