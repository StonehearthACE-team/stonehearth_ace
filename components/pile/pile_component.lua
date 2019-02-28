local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local component_info_lib = require 'stonehearth_ace.lib.component_info.component_info_lib'

local PileComponent = class()

function PileComponent:initialize()
   self._sv.items = {}
   
   local json = radiant.entities.get_json(self)
   self._harvest_rate = json.harvest_rate or 1
end

function PileComponent:is_empty()
   return next(self._sv.items) == nil
end

function PileComponent:set_items(items)
   self._sv.items = {}
   for _, item in pairs(items) do
      self:_add_item(item)
   end
   self.__saved_variables:mark_changed()

   self:_update_component_info()
end

-- store the necessary information about the item
function PileComponent:_add_item(item)
   local iq_comp = item:get_component('stonehearth:item_quality')
   local item_data = {
      uri = item:get_uri(),
      quality = iq_comp and iq_comp:get_quality() or 1,
      author = iq_comp and iq_comp:get_author_name(),
      author_type = iq_comp and iq_comp:get_author_type(),
   }
   item_quality_lib.apply_quality(self._entity, item_data.quality)
   table.insert(self._sv.items, item_data)
end

-- harvest items based on harvest rate
function PileComponent:harvest_once(owner)
   local items = {}
   local item_count = 0
   for i = 1, self._harvest_rate do
      local item = self:_harvest_next(owner)
      if item then
         items[item:get_id()] = item
         item_count = item_count + 1
      else
         break
      end
   end

   -- check to see if we need to downgrade quality
   self:_update_quality()
   self.__saved_variables:mark_changed()

   self:_update_component_info()

   return items, item_count
end

-- harvest a single item
function PileComponent:_harvest_next(owner)
   -- FILO / LIFO
   local item_data = table.remove(self._sv.items)
   local item = radiant.entities.create_entity(item_data.uri, { owner = owner or self._entity })
   item_quality_lib.apply_quality(item, item_data.quality, { author = item_data.author, author_type = item_data.author_type })

   return item
end

function PileComponent:_update_quality()
   local quality = 1
   for _, item in ipairs(self._sv.items) do
      if item.quality > quality then
         quality = item.quality
      end
   end

   if quality < radiant.entities.get_item_quality(self._entity) then
      self._entity:remove_component('stonehearth:item_quality')
      item_quality_lib.apply_quality(self._entity, quality)
   end
end

function PileComponent:_update_component_info()
   local comp_info = self._entity:add_component('stonehearth_ace:component_info')

   comp_info:set_component_general_hidden('stonehearth:resource_node', true)

   comp_info:set_component_detail('stonehearth_ace:pile', 'harvest_rate',
         'stonehearth_ace:component_info.stonehearth_ace.pile.harvest_rate', { harvest_rate = self._harvest_rate })
   
   comp_info:set_component_detail('stonehearth_ace:pile', 'items', {
         type = 'item_list',
         items = self._sv.items,
         header = 'stonehearth_ace:component_info.stonehearth_ace.pile.item_list_header'
      }, { item_count = #self._sv.items })
end

return PileComponent