--[[
   The ACE Mercantile service replaces the normal functionality for market/shop stalls.
   Instead of being individually stall-based, the service handles what merchants should
   visit each day, and those merchants are then spawned with this component and given
   the data for their particular shop and preferred market stall to set up at.
]]

local MerchantComponent = class()

local log = radiant.log.create_logger('merchant_component')

function MerchantComponent:create()
   stonehearth.ai:inject_ai(self._entity, { ai_packs = { 'stonehearth_ace:ai_pack:merchant' } })
end

function MerchantComponent:restore()
   self._is_restore = true
   stonehearth.ai:inject_ai(self._entity, { ai_packs = { 'stonehearth_ace:ai_pack:merchant' } })

   if self._sv._stall then
      self._sv.stall = self._sv._stall
      self._sv._stall = nil
      self.__saved_variables:mark_changed()
   end
end

function MerchantComponent:post_activate()
   if self._is_restore and self._sv._should_depart then
      self:set_should_depart()
   else
      self:_load_merchant_data()
      self:_update_commands()
   end
end

function MerchantComponent:destroy()
   self:_destroy_shop()
end

function MerchantComponent:_load_merchant_data()
   self._merchant_data = stonehearth_ace.mercantile:get_merchant_data(self._sv.merchant) or {}
end

function MerchantComponent:get_player_id()
   return self._sv.player_id
end

function MerchantComponent:get_merchant_data()
   return self._merchant_data
end

function MerchantComponent:get_stall_tier()
   return self._merchant_data.min_stall_tier
end

function MerchantComponent:get_required_stall()
   return self._merchant_data.required_stall
end

function MerchantComponent:is_exclusive()
   return self._merchant_data.is_exclusive
end

function MerchantComponent:set_merchant_data(player_id, merchant_data)
   self._sv.player_id = player_id
   self._sv.merchant = merchant_data.key
   self.__saved_variables:mark_changed()

   self:_load_merchant_data()
   if merchant_data.use_shop_description then
      --log:debug('%s using shop description: %s', self._entity, tostring(merchant_data.shop_info.name))
      radiant.entities.set_description(self._entity, 'i18n(stonehearth_ace:entities.humans.npc_merchant.shop_prefix)' .. merchant_data.shop_info.name)
   end
   
   local options = radiant.shallow_copy(merchant_data.shop_info.inventory)
   options.merchant_options = merchant_data.shoptions or {}

   local persistence_job = options.merchant_options.persistence_job
   if persistence_job then
      -- if a persistence job was specified, try to find a match in persistence data
      local crafter = stonehearth_ace.persistence:get_random_crafter(persistence_job, 1)
      if crafter then
         options.persistence_data = {
            name = crafter.name,
            level = crafter.level,
            best_crafts = crafter.best_crafts,
            town = {
               save_id = crafter.town.save_id,
               player_id = crafter.town.player_id,
               town_name = crafter.town.town_name,
            },
         }
      end
   end
   self._sv._shop = stonehearth.shop:create_shop(player_id, merchant_data.shop_info.name, options)

   self._entity:add_component('stonehearth:commands'):add_command('stonehearth_ace:commands:show_shop')
   self:_update_commands()
   
   --self:show_bulletin(true)
end

function MerchantComponent:get_current_stall()
   return self._sv.stall
end

function MerchantComponent:get_shop()
   return self._sv._shop
end

function MerchantComponent:show_bulletin(initial)
   if self._sv._bulletin then
      if self._sv._bulletin.__destroyed then
         self:_destroy_bulletin()
      else
         -- the bulletin exists, but we want to make sure it pops back up
         -- sadly, the easiest way to do this is to just destroy it and make it again
         -- otherwise we'd have to rework how commands handle call/fire_event and
         -- do both for this; this way it's all in one place
         self:_destroy_bulletin()
         --return
      end
   end

   local data = {
      shop = self._sv._shop,
      title = self._merchant_data.shop_info.title,
      closed_callback = '_on_shop_closed',
      skip_notification = not initial
   }

   self._sv._bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
                        :set_ui_view('StonehearthShopBulletinDialog')
                        :set_callback_instance(self)
                        :set_data(data)
                        :set_type(self:is_exclusive() and 'shop_exclusive' or 'shop')
end

function MerchantComponent:_on_shop_closed()
   self:_destroy_bulletin()
end

function MerchantComponent:_destroy_shop()
   log:debug('destroying shop for %s...', self._entity)
   local shop = self._sv._shop
   if shop then
      stonehearth.shop:destroy_shop(shop)
      self._sv._shop = nil
      self:_update_commands()
   end

   self:_destroy_bulletin()
   self:take_down_from_stall()
end

function MerchantComponent:_destroy_bulletin()
   local bulletin = self._sv._bulletin
   if bulletin then
      log:debug('destroying shop bulletin for %s', self._entity)
      stonehearth.bulletin_board:remove_bulletin(bulletin)
      self._sv._bulletin = nil
   end
end

function MerchantComponent:take_down_from_stall()
   local stall = self._sv.stall
   if stall then
      self._sv.stall = nil
      self.__saved_variables:mark_changed()

      local stall_comp = stall:get_component('stonehearth_ace:market_stall')
      if stall_comp then
         stall_comp:reset()
      end
   end
end

function MerchantComponent:set_up_at_stall(stall)
   if stall ~= self._sv.stall then
      self:take_down_from_stall()
      local stall_comp = stall:get_component('stonehearth_ace:market_stall')
      if stall_comp then
         self._sv.stall = stall
         return stall_comp:set_merchant(self._entity)
      end
   end
end

function MerchantComponent:finish_stall_setup()
   self.__saved_variables:mark_changed()
end

function MerchantComponent:should_depart()
   return self._sv._should_depart
end

function MerchantComponent:set_should_depart()
   self._sv._should_depart = true
   self:_update_commands()
   
   self._entity:get_component('stonehearth:ai')
      :get_task_group('stonehearth_ace:task_groups:merchant')
         :create_task('stonehearth_ace:merchant:depart', {})
            :start()
end

function MerchantComponent:_update_commands()
   -- enable or disable the command that opens the shop bulletin
   local shop_commands = self._entity:get_component('stonehearth:commands')

   if shop_commands then
      shop_commands:set_command_enabled('stonehearth_ace:commands:show_shop', self._sv._shop and not self._sv._should_depart)
   end
end

return MerchantComponent
