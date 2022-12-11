local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local constants = require 'stonehearth.constants'
local mercantile_constants = constants.mercantile

local MarketStallComponent = class()

local STALL_MODEL_NAME = 'stonehearth_ace:market_stall:model'

function MarketStallComponent:activate()
   self._json = radiant.entities.get_json(self) or {}
   -- we want unique stalls to be totally separate from tier stalls; if no explicit tier, it's unique
   self._tier = self._json.tier  -- or 1
   self._setup_effect = self._json.setup_effect
   self._teardown_effect = self._json.setup_effect or self._setup_effect
   self._stall_models = self._json.stall_models or {}

   -- register with mercantile service when it's in the world, unregister when out
   self._parent_trace = self._entity:add_component('mob'):trace_parent('market stall added or removed')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               stonehearth_ace.mercantile:unregister_merchant_stall(self._entity)
               self:set_merchant(nil)
            else
               --we were just added to the world
               stonehearth_ace.mercantile:register_merchant_stall(self._entity)
            end
         end)
      :push_object_state()
end

function MarketStallComponent:post_activate()
   if self._sv._is_setting_up then
      self:_finish_setting_up()
   else
      -- make sure the base game shop commands are removed
      self:_update_commands()
   end
end

function MarketStallComponent:destroy()
   if self._sv._merchant and self._sv._merchant:is_valid() then
      local merchant_component = self._sv._merchant:get_component('stonehearth_ace:merchant')
      if merchant_component then
         merchant_component:take_down_from_stall()
      end
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function MarketStallComponent:get_merchant()
   return self._sv._merchant
end

function MarketStallComponent:set_merchant(merchant)
   if merchant ~= self._sv._merchant then
      self._sv._merchant = merchant
      self._sv._is_setting_up = true

      local effect = merchant and self._setup_effect or self._teardown_effect
      if effect then
         self._effect = radiant.effects.run_effect(self._entity, effect)
         self._effect:set_finished_cb(function() self:_finish_setting_up() end)
         return true
      else
         self:_finish_setting_up()
      end

      stonehearth.ai:reconsider_entity(self._entity, 'active merchant changed')
   end
end

function MarketStallComponent:_finish_setting_up()
   self._effect = nil
   self._sv._is_setting_up = nil
   self._sv._active = self._sv._merchant and self._sv._merchant:is_valid()
   self:_set_stall_model()
   self:_update_commands()
end

function MarketStallComponent:get_tier()
   return self._tier
end

function MarketStallComponent:reset()
   -- if there's a merchant associated with this stall, clear them out
   self:set_merchant(nil)
end

function MarketStallComponent:_set_stall_model()
   -- set up or clear out any extra stall models, entities for show, etc.
   local models

   local merchant = self._sv._merchant
   local merchant_component = merchant and merchant:get_component('stonehearth_ace:merchant')
   local merchant_data = merchant_component and merchant_component:get_merchant_data()
   local stall_model = merchant_data and merchant_data.stall_model
   -- only want models set if there is a merchant here still
   models = merchant and self._stall_models[stall_model or 'default']

   local model_data = models and models.model_data
   if model_data then
      self._entity:add_component('stonehearth_ace:models'):add_model(STALL_MODEL_NAME, model_data)
   else
      local models_component = self._entity:get_component('stonehearth_ace:models')
      if models_component then
         models_component:remove_model(STALL_MODEL_NAME)
      end
   end

   self:_setup_entity_points(models and models.entity_points, merchant_data and merchant_data.shop_display_items)
end

function MarketStallComponent:_setup_entity_points(points, inventory_override)
   -- have entity points where sample wares can be rendered
   --[[
      {
         "bone": "shop_item_1"
         "min_rarity": "uncommon",
         "min_quality": 1
      }
   ]]

   -- first clear out any existing ones
   local player_id = self._entity:get_player_id()
   local entity_container = self._entity:get_component('entity_container')
   if entity_container then
      for id, child in entity_container:each_attached_item() do
         if child and child:is_valid() and radiant.entities.get_player_id(child) ~= player_id then
            radiant.entities.destroy_entity(child)
         end
      end
   end

   if points and #points > 0 then
      entity_container = self._entity:add_component('entity_container')
      local merchant_player_id = self._sv._merchant:get_player_id()
      local shop_inventory = inventory_override or self._sv._merchant:get_component('stonehearth_ace:merchant'):get_shop():get_shop_inventory()
      -- cache item sets in case points want items with the same limitations (probably common)
      local item_sets = {}
      local used_items = {}
      for _, point in ipairs(points) do
         if point.bone_name then
            -- try to find an item in the shop that fits the requirements for this bone
            local min_rarity_rank = mercantile_constants.RARITY_RANKS[point.min_rarity or 'common']
            local min_quality = point.min_quality or 1
            local key = tostring(min_rarity_rank) .. ':' .. tostring(min_quality)
            local items = item_sets[key]
            if not items then
               items = self:_get_item_set(shop_inventory, min_rarity_rank, min_quality)
               item_sets[key] = items
            end

            if not items:is_empty() then
               local uri
               while not items:is_empty() do
                  uri = items:choose_random()
                  items:remove(uri)
                  if not used_items[uri] then
                     break
                  end
               end
               used_items[uri] = true
               -- make sure we only bother creating the iconic entity
               local catalog_data = stonehearth.catalog:get_catalog_data(uri)
               if catalog_data then
                  uri = catalog_data.iconic_uri or uri
                  local item = radiant.entities.create_entity(uri, {owner = merchant_player_id})
                  entity_container:add_child_to_bone(item, point.bone_name)
               end
            end
         end
      end
   end
end

function MarketStallComponent:_get_item_set(shop_inventory, min_rarity_rank, min_quality)
   -- go through the shop inventory and add all the qualifying items to a weighted set, with quantity as weight
   local items = WeightedSet(rng)
   for key, item in pairs(shop_inventory) do
      if (item.item_quality or 1) >= min_quality and
            mercantile_constants.RARITY_RANKS[(item.rarity or 'common')] >= min_rarity_rank then
         items:add(item.uri, 1)
      end
   end

   return items
end

function MarketStallComponent:_update_commands()
   -- enable or disable the command that opens the shop bulletin
   local shop_commands = self._entity:get_component('stonehearth:commands')

   if shop_commands then
      shop_commands:remove_command('stonehearth:commands:trigger_trader_encounter')
      shop_commands:remove_command('stonehearth:commands:call_trader')
      shop_commands:remove_command('stonehearth:commands:show_shop')
      shop_commands:set_command_enabled('stonehearth_ace:commands:show_shop', self._sv._active)
   end
end

return MarketStallComponent
