local AceBuffsComponent = class()

function AceBuffsComponent:activate()
   if not self._sv.disallowed_buffs then
      self._sv.disallowed_buffs = {}
   end
end

function AceBuffsComponent:add_buff(uri, options)
   assert(not string.find(uri, '%.'), 'tried to add a buff with a uri containing "." Use an alias instead')

   if self:_buff_is_disallowed(uri) then
      return -- don't add this buff if it's disallowed by other active buffs
   end

   local json = radiant.resources.load_json(uri, true)
   if self:_buff_on_cooldown(json) then
      return -- don't add this buff if it's cooldown buff is still active
   end

   local buff
   local cur_count = self._sv.ref_counts[uri]
   if not cur_count then
      self._sv.ref_counts[uri] = 1
   else
      self._sv.ref_counts[uri] = cur_count + 1
   end
   local ref_count = self._sv.ref_counts[uri]

   if ref_count == 1 then
      buff = radiant.create_controller('stonehearth:buff', self._entity, uri, json, options)
      self._sv.buffs[uri] = buff

      -- if this buff disallows others, track that and remove any that are currently active
      if json.disallowed_buffs then
         for _, dis_buff in ipairs(json.disallowed_buffs) do
            local cur_disallowed = self._sv.disallowed_buffs[dis_buff]
            if not cur_disallowed then
               cur_disallowed = {}
               self._sv.disallowed_buffs[dis_buff] = cur_disallowed
            end
            cur_disallowed[uri] = true
            if self:has_buff(dis_buff) then
               self:remove_buff(dis_buff, true)
            end
         end
      end

      self.__saved_variables:mark_changed()

      radiant.events.trigger_async(self._entity, 'stonehearth:buff_added', {
            entity = self._entity,
            uri = uri,
            buff = buff,
         })
   else
      buff = self._sv.buffs[uri]
      assert(buff)
      if buff:on_repeat_add(options) then
         self.__saved_variables:mark_changed()
      end
   end

   return buff
end

function AceBuffsComponent:remove_buff(uri, remove_all_stacks)
   local cur_count = self._sv.ref_counts[uri]
   if not cur_count or cur_count == 0 then
      return
   end

   local ref_count = cur_count - 1

   if ref_count == 0 or remove_all_stacks then
      self._sv.ref_counts[uri] = 0 -- Just in case we're doing a remove_all_stacks
      local buff = self._sv.buffs[uri]
      if buff then
         local json = radiant.resources.load_json(uri, true)
         if json.disallowed_buffs then
            for _, dis_buff in ipairs(json.disallowed_buffs) do
               local cur_disallowed = self._sv.disallowed_buffs[dis_buff]
               if cur_disallowed then
                  cur_disallowed[uri] = nil
               end
               if not next(cur_disallowed) then
                  self._sv.disallowed_buffs[dis_buff] = nil
               end
            end
         end

         self._sv.buffs[uri] = nil
         buff:destroy()
         self.__saved_variables:mark_changed()

         radiant.events.trigger_async(self._entity, 'stonehearth:buff_removed', uri)
      end
   end
end

function AceBuffsComponent:_buff_is_disallowed(uri)
   return self._sv.disallowed_buffs[uri] ~= nil
end

return AceBuffsComponent
