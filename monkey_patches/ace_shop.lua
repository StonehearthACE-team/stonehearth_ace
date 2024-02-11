local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local PopulationFaction = require 'stonehearth.services.server.population.population_faction'

local Shop = require 'stonehearth.services.server.shop.shop'
local AceShop = class()
local rng = _radiant.math.get_default_rng()
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local constants = require 'stonehearth.constants'
local mercantile_constants = constants.mercantile
local log = radiant.log.create_logger('shop')

local rounding_min_threshold = constants.shop.SHOP_VALUE_ROUNDING_MIN_THRESHOLD or 50

local function round_cost(value)
   if value >= rounding_min_threshold then
      -- Round to the nearest 5.
      value = math.max(5, (math.ceil(value / 5) * 5))
   else
      value = math.max(2, math.ceil(value))
   end
   return value
end

function AceShop:_get_item_quantity_to_add(uri, entity_description, inventory_spec, is_material_sellable)
   if self:_item_matches_inventory_spec(inventory_spec, uri, entity_description, is_material_sellable) then
      local min = inventory_spec.quantity.min
      local max = inventory_spec.quantity.max

      -- Towns with the cunning bonus get more stock.
      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         local cunning_bonus = town:get_town_bonus('stonehearth:town_bonus:cunning')
         if cunning_bonus then
            min = cunning_bonus:apply_trader_quantity_bonus(min)
            max = cunning_bonus:apply_trader_quantity_bonus(max)
         end
      end

      local quantity = rng:get_int(min, max)
      if quantity > 0 then
         return quantity
      end
   end
   return nil
end

function AceShop:_item_matches_inventory_spec(inventory_spec, uri, entity_description, is_material_sellable)
   -- check if entity matches shop rarity
   local rarities = self._sv.rarity
   if entity_description.rarity then
      if not rarities[entity_description.rarity] then
         return false
      end
   end

   local matches = false
   -- check if the entity in the list of items
   if inventory_spec.items then
      local entity_path = radiant.resources.convert_to_canonical_path(uri)
      for _, sellable_uri in ipairs(inventory_spec.items) do
         local item_path = radiant.resources.convert_to_canonical_path(sellable_uri)
         if item_path == entity_path then
            matches = true
            break
         end
      end
   end

   if not matches then
      -- check if the entity passes any filter
      if is_material_sellable and inventory_spec.items_matching then
         for key, filter in pairs(inventory_spec.items_matching) do
            if stonehearth.shop:inventory_filter_fn(entity_description, filter) then
               matches = true
               break
            end
         end
      end
   end

   if not matches then
      return false
   end

   if entity_description.shopkeeper_level and entity_description.shopkeeper_level > self._sv.shopkeeper_level then
      return false
   end

   return true
end

-- ACE: handle new "wanted_items", "persistence_data", "max_unique" quantity option, and rarity weights
function AceShop:stock_shop()
   -- we've changed bought items to spawn directly to the player so we don't need the escrow; go ahead and destroy it
   if radiant.entities.exists(self._sv.escrow_entity) then
      radiant.entities.destroy_entity(self._sv.escrow_entity)
   end
   self._sv.escrow_entity = nil

   -- get a table of all the items which can appear in a shop
   local rarity_weights = mercantile_constants.RARITY_WEIGHTS
   local rarity_weights_override = {}
   local all_sellable_items = stonehearth.catalog:get_shop_buyable_items()
   local all_specific_sellable_items = stonehearth.catalog:get_shop_specific_buyable_items()

   self._sv.shop_inventory = {}
   self._sv.wanted_items = {}

   local shop_sold_items = {}
   local persistence_items = {}
   
   local options = self._sv.options
   local merchant_options = options.merchant_options
   if merchant_options then
      if merchant_options.rarity_weights then
         rarity_weights_override = merchant_options.rarity_weights
      end
   end

   -- go through separately for each shop inventory entry and find items to add
   -- this way we can also limit the number of unique items for a particular entry
   -- and another entry could separately add some of the same items without getting cut off
   for _, inventory_spec in pairs(options.entries) do
      local entry_items = {}

      for uri, _ in pairs(all_specific_sellable_items) do
         local entity_description = stonehearth.catalog:get_catalog_data(uri)
         if entity_description.sell_cost > 0 then
            local quantity = self:_get_item_quantity_to_add(uri, entity_description, inventory_spec, all_sellable_items[uri])
            if quantity then
               table.insert(entry_items, {
                  uri = uri,
                  entry = inventory_spec,
                  quantity = quantity,
                  description = entity_description,
                  rarity = entity_description.rarity or 'common'
               })
            end
         end
      end

      -- check if there's a max_unique setting for this entry's quantity
      local max_unique = inventory_spec.quantity.max_unique
      if max_unique and max_unique < #entry_items then
         -- randomly limit the number of different items to this amount
         local set = WeightedSet(rng)
         for _, item in ipairs(entry_items) do
            set:add(item, rarity_weights_override[item.rarity] or rarity_weights[item.rarity])
         end

         local limited_items = {}
         while #limited_items < max_unique do
            local item = set:choose_random()
            set:remove(item)
            table.insert(limited_items, item)
         end
         entry_items = limited_items
      end

      -- finally add the resulting items to the shop
      for _, item in ipairs(entry_items) do
         self:_add_entity_to_shop_sold_items(shop_sold_items, item)
      end
   end

   for rarity, entities in pairs(shop_sold_items) do
      local rarity_weight = math.ceil(rarity_weights_override[rarity] or rarity_weights[rarity])
      for uri, shop_item_data in pairs(entities) do
         -- for each item, have a chance to include it based on its rarity
         local chance = rng:get_int(1, rarity_weights_override.common or rarity_weights.common)
         if chance <= rarity_weight then
            local shop_item_description = shop_item_data.entity_description
            local quantity = shop_item_data.shop_data.quantity
            local cost_multiplier = 1
            if shop_item_data.shop_data.entry.price_multiplier then
               cost_multiplier = shop_item_data.shop_data.entry.price_multiplier
            elseif options.overall_price_multiplier then
               cost_multiplier = options.overall_price_multiplier
            end

            local cost = shop_item_description.sell_cost * cost_multiplier

            -- Add it to the shop inventory
            local fine_chance = shop_item_data.shop_data.entry.fine_item_chance or stonehearth.constants.shop.DEFAULT_FINE_ITEM_CHANCE
            local fine_quantity = 0
            if fine_chance > 0 then
               if fine_chance == 1 then
                  fine_quantity = quantity
               else
                  for i = 1, quantity do
                     if fine_chance > rng:get_real(0, 1) then
                        fine_quantity = fine_quantity + 1
                     end
                  end
               end
            end
            if fine_quantity > 0 then
               self:_add_item_to_inventory(uri, shop_item_description, cost, 2, fine_quantity)
            end
            if fine_quantity < quantity then
               self:_add_item_to_inventory(uri, shop_item_description, cost, 1, quantity - fine_quantity)
            end
         end
      end
   end

   -- reorganized so that wanted items are added last
   -- and can exclude any that are now found in the shop's inventory
   if merchant_options then
      if merchant_options.persistence_data then
         -- if a persistence job was defined, try to find an appropriate match
         -- add some of the recent crafts from that crafter to the shop, and set the town name, crafter name, and description
         self._sv.description = 'i18n(stonehearth_ace:ui.game.bulletin.shop.persistence.crafter_description)'
         self._sv.description_i18n_data = {
            crafter_name = merchant_options.persistence_data.name,
            town_name = merchant_options.persistence_data.town.town_name,
         }

         -- randomly select one of their best crafts
         local best_crafts = merchant_options.persistence_data.best_crafts
         if #best_crafts > 0 then
            local craft_entry = self:_get_sellable_item(all_specific_sellable_items, best_crafts)
            if craft_entry then
               -- the idea is that the crafter made a bunch of lower quality versions of this item
               -- while trying to make this high quality one; so they're selling the single high quality one
               -- along with all the lower quality ones they made along the way
               local entity_description = stonehearth.catalog:get_catalog_data(craft_entry.uri)
               if entity_description.sell_cost > 0 then
                  local cost = entity_description.sell_cost * mercantile_constants.PERSISTENCE_ITEM_PRICE_FACTOR
                  local quality_counts = mercantile_constants.PERSISTENCE_ITEM_QUALITY_COUNTS

                  self:_add_item_to_inventory(craft_entry.uri, entity_description, cost, craft_entry.quality, 1)

                  for quality = 1, math.min(craft_entry.quality - 1, #quality_counts) do
                     self:_add_item_to_inventory(craft_entry.uri, entity_description, cost, quality, quality_counts[quality])
                  end
               end
            end
         end
      end

      if merchant_options.wanted_items then
         local wanted_items = {}
         local maybe_wanted_items = {}
         for _, item in ipairs(merchant_options.wanted_items) do
            -- copy the entries because we'll want to modify the quantity
            -- check if this item isn't already in the shop's inventory
            if (item.uri and all_specific_sellable_items[item.uri] and not self:_is_selling_item(item.uri)) or
                  (item.material and not self:_is_selling_material(item.material)) then
               if not item.chance then
                  table.insert(wanted_items, item)
               elseif rng:get_real(0, 1) < item.chance then
                  table.insert(maybe_wanted_items, item)
               end
            end
         end

         while #maybe_wanted_items > 0 and (not merchant_options.max_wanted_items or #wanted_items < merchant_options.max_wanted_items) do
            table.insert(wanted_items, table.remove(maybe_wanted_items, rng:get_int(1, #maybe_wanted_items)))
         end

         local def_price_factor = mercantile_constants.DEFAULT_WANTED_ITEM_PRICE_FACTOR
         for _, item in ipairs(wanted_items) do
            table.insert(self._sv.wanted_items, 
               {
                  material = item.material,
                  uri = item.uri,
                  price_factor = item.price_factor or def_price_factor,
                  max_quantity = item.max_quantity,
                  quantity = 0,
               })
         end
      end
   end

   self.__saved_variables:mark_changed()
end

function AceShop:sell_item(uri, quality, quantity)
   local sell_quantity = quantity or 1

   --the items we can sell should come from the sellable item tracker, not the whole inventory
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   local sellable_item_tracker = inventory:get_item_tracker('stonehearth:sellable_item_tracker')
   local tracking_data = sellable_item_tracker:get_tracking_data()

   if not tracking_data:contains(uri) then
      -- Somehow this item is not in the tracker. maybe we sold off all of them but got an extra sell message
      return false
   end

   local sellable_items = tracking_data:get(uri)
   local shopkeeper_gold = self._sv.shopkeeper_gold
   local item_quality_entry = sellable_items.item_qualities[tostring(quality)]
   if not item_quality_entry then
      -- Same reason as above
      log:error('No entry found in sellable items for item quality %s', quality)
      return false
   end

   local item_cost = item_quality_entry.resale
   -- if the merchant is selling this item, also apply their unwanted modifier
   if self:_is_selling_item(uri) then
      item_cost = item_cost * mercantile_constants.DEFAULT_UNWANTED_ITEM_PRICE_FACTOR
   end

   local removed_from_containers = {}
   local total_gold = 0

   for entity_id, entity in pairs(item_quality_entry.items) do
      -- "sell" each entity by destroying it, until we've sold the requested amount or run out of entities

      -- also check it against the wanted_items to modify the price and reduce the max quantity if relevant
      -- this can change every time if there are multiple wanted items that could apply to this uri (e.g., uri- and material-based)
      local actual_cost = item_cost
      local wanted_items = self:_get_wanted_items_entry(uri)
      if wanted_items then
         actual_cost = item_cost * wanted_items.price_factor
      end
      -- rounding is applied after wanted and unwanted item bonuses
      actual_cost = math.max(1, math.floor(actual_cost + 0.5))

      if sell_quantity == 0 or shopkeeper_gold < actual_cost then
         break
      end
      local storage = inventory:public_container_for(entity)
      if storage then
         removed_from_containers[storage:get_id()] = storage
      end

      radiant.entities.kill_entity(entity)
      total_gold = total_gold + actual_cost
      shopkeeper_gold = shopkeeper_gold - actual_cost
      sell_quantity = sell_quantity - 1

      if wanted_items then
         wanted_items.quantity = wanted_items.quantity + 1
      end
   end

   -- notify containers that items were removed from it, as it is possible they were full and now have room
   for _, storage in pairs(removed_from_containers) do
      stonehearth.ai:reconsider_entity(storage, 'sold item was removed from storage')
   end

   self._sv.shopkeeper_gold = shopkeeper_gold
   self.__saved_variables:mark_changed()
   -- give gold to the player
   inventory:add_gold(total_gold)
   inventory:add_trade_gold_earned(total_gold)

   radiant.events.trigger_async(self, 'stonehearth:item_sold', {item_uri = uri, item_cost = item_cost, quantity = quantity - sell_quantity})
   return true
end

function AceShop:_get_sellable_item(all_sellable, items)
   local order = {}
   for i, item in ipairs(items) do
      if i > 1 then
         table.insert(order, rng:get_int(1, #order + 1), item)
      else
         table.insert(order, item)
      end
   end
   for i, item in ipairs(order) do
      if all_sellable[item.uri] then
         return item
      end
   end
end

function AceShop:_is_selling_item(uri)
   -- WARNING: hard-coding max item quality as 4 (masterwork) for checks
   for quality = 1, 4 do
      local key = self:_key_from_uri_and_quality(uri, quality)
      if self._sv.shop_inventory[key] then
         return true
      end
   end
   return false
end

function AceShop:_is_selling_material(material)
   -- check all shop inventory items to see if an item with the given material is already present
   for _, entry in pairs(self._sv.shop_inventory) do
      if stonehearth.catalog:is_material(entry.uri, material) then
         return true
      end
   end
   return false
end

function AceShop:_get_wanted_items_entry(uri)
   -- if we want this item for its uri or material, return highest price factor option available
   local best_match
   for _, item in ipairs(self._sv.wanted_items) do
      -- we do these checks in an unconventional order for efficiency
      -- simple arithmetic is an easier check that can avoid the is_material check
      -- first check if there's any quantity left (or unlimited quantity)
      if not item.max_quantity or item.max_quantity > item.quantity then
         -- then check if it's better than our current best match
         if not best_match or item.price_factor > best_match.price_factor then
            -- finally check if it's generally a match
            if item.uri == uri or (item.material and stonehearth.catalog:is_material(uri, item.material)) then
               best_match = item
            end
         end
      end
   end

   return best_match
end

 -- ACE: since the shop is available the whole time the merchant is in town and can be reopened if closed,
 -- just spawn items immediately rather than storing them in escrow
 -- also if using persistence data, use that town's name rather than randomly generating one
 function AceShop:_spawn_items(uri, quality, quantity)
   local escrow_storage_component, default_storage, location, items
   if radiant.entities.exists(self._sv.escrow_entity) then
      escrow_storage_component = self._sv.escrow_entity:get_component('stonehearth:storage')
   else
      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         items = {}
         default_storage = town:get_default_storage()
         location = town:get_landing_location()
      else
         log:error('could not spawn %s of %s (quality %s)! no escrow or town matching player id %s', quantity, uri, quality, self._sv.player_id)
         return false
      end
   end
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)

   for i = 1, quantity do
      local item = radiant.entities.create_entity(uri, { owner = self._sv.player_id })
      if quality > 1 then
         local author = self:_get_quality_item_author()
         item_quality_lib.apply_quality(item, quality, {
            author = author,
            author_type = 'place',
         })
      end
      local root, iconic = entity_forms.get_forms(item)
      item = iconic or root or item
      if escrow_storage_component then
         escrow_storage_component:add_item(item)
      else
         items[item:get_id()] = item
      end
   end

   if items then
      self:_dump_items(items, location, default_storage)
   end

   return true
end

function AceShop:_get_quality_item_author()
   -- if using persistence data, use that town name
   if self._sv.town_name then
      return self._sv.town_name
   end

   -- alternately maybe try just selecting a random persistence town name?
   if rng:get_real(0, 1) <= mercantile_constants.PERSISTENCE_TOWN_NAME_CHANCE then
      local town = stonehearth_ace.persistence:get_random_town()
      if town then
         return town.town_name
      end
   end

   -- otherwise use base game code:
   -- Generate a town name from which this item originates.
   local kingdoms = radiant.resources.load_json('stonehearth:playable_kingdom_index').kingdoms
   local chosen_index = rng:get_int(1, radiant.size(kingdoms))
   local index = 1
   local kingdom
   for _, uri in pairs(kingdoms) do
      if index == chosen_index then
         kingdom = uri
         break
      end
      index = index + 1
   end
   return PopulationFaction.generate_town_name_from_pieces(radiant.resources.load_json(kingdom).town_pieces)
end

function AceShop:dump_escrow_at_location(location)
   if not radiant.entities.exists(self._sv.escrow_entity) then
      return false
   end

   local default_storage
   if not location then
      local town = stonehearth.town:get_town(self._sv.player_id)
      if town then
         default_storage = town:get_default_storage()
         location = town:get_landing_location()
      end
      if not location then
         return false
      end
   end

   local escrow_storage_component = self._sv.escrow_entity:get_component('stonehearth:storage')
   local escrow_items = escrow_storage_component:get_items()
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   if escrow_items then
      local items = radiant.shallow_copy(escrow_items)
      for id, item in pairs(items) do
         if item and item:is_valid() then
            escrow_storage_component:remove_item(id)
         end
      end

      self:_dump_items(items, location, default_storage)
   end
end

function AceShop:_dump_items(items, location, inputs)
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   -- check for and remove any pets
   for id, item in pairs(items) do
      if item and item:is_valid() then
         -- If the purchased "item" has AI, it's a pet. Remove it from the inventory and let it befriend a random townsperson.
         if item:get_component('stonehearth:ai') then
            local nearby_location = radiant.terrain.find_placement_point(location, 1, 7)
            radiant.terrain.place_entity(item, nearby_location)
            
            items[id] = nil
            inventory:remove_item(id)
            local pet_component = item:add_component('stonehearth:pet')
            pet_component:convert_to_pet(self._sv.player_id)
            local citizens = stonehearth.population:get_population(self._sv.player_id):get_citizens()
            local citizen_ids = citizens:get_keys()
            local citizen_id = citizen_ids[rng:get_int(1, #citizen_ids)]
            pet_component:set_owner(citizens:get(citizen_id))
         end
      end
   end

   local options = {
      inputs = inputs,
      spill_fail_items = true,
      require_matching_filter_override = true,
   }
   radiant.entities.output_spawned_items(items, location, 1, 7, options)
end

function AceShop:_add_entity_to_shop_sold_items(shop_sold_items, item)
   local rarity = item.rarity

   local rarity_entry = shop_sold_items[rarity]
   if not rarity_entry then
      rarity_entry = {}
      shop_sold_items[rarity] = rarity_entry
   end

   local rarity_item = rarity_entry[item.uri]
   if not rarity_item then
      rarity_item = {
         entity_description = item.description,
         shop_data = item,
      }
      rarity_entry[item.uri] = rarity_item
   else
      -- add the quantity from this entry
      rarity_item.shop_data.quantity = rarity_item.shop_data.quantity + item.quantity
   end
end

function AceShop:_add_item_to_inventory(uri, description, cost, quality, quantity)
   if not description.materials and description.category ~= 'pets' then
      -- no materials! bad item!
      return
   end
   
   local key = self:_key_from_uri_and_quality(uri, quality)
   local entry = self._sv.shop_inventory[key]
   if not entry then
      entry = {
         uri = uri,
         rarity = description.rarity or 'common',
         display_name = description.display_name,
         description = description.description,
         icon = description.icon,
         cost = round_cost(quality < 2 and cost or radiant.entities.apply_item_quality_bonus('net_worth', cost, quality)),
         category = description.category or 'none',
         num = quantity,
         item_quality = quality,
      }
      self._sv.shop_inventory[key] = entry
   else
      entry.num = entry.num + quantity
   end
end

return AceShop
