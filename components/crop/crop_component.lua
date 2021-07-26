--[[
   Every time the crop grows, update its resource node resource. More mature crops
   yield better resources.
]]
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local rng = _radiant.math.get_default_rng()
local CropComponent = class()

function CropComponent:initialize()
   -- Initializing save variables
   self._sv.harvestable = false
   self._sv.stage = nil
   self._sv.product = nil
   self._sv._field = nil
   self._sv._field_offset_x = 0
   self._sv._field_offset_y = 0

   self:_load_json()
end

function CropComponent:_load_json()
   self._json = radiant.entities.get_json(self) or {}
   self._resource_pairings = self._json.resource_pairings
   self._harvest_threshhold = self._json.harvest_threshhold
   self._stacks_per_harvest = self._json.stacks_per_harvest or 1
end

function CropComponent:restore()
   self._is_restore = true

   if self._sv.megacrop_chance then
      self._sv._megacrop_chance = self._sv.megacrop_chance
      self._sv.megacrop_chance = nil
   end
   if self._sv.consider_megacrop then
      self._sv._consider_megacrop = self._sv.consider_megacrop
      self._sv.consider_megacrop = nil
   end
   if self._sv.is_megacrop then
      self._sv._is_megacrop = self._sv.is_megacrop
      self._sv.is_megacrop = nil
   end
end

function CropComponent:activate()
   if self._entity:get_component('stonehearth:growing') then
      self._growing_listener = radiant.events.listen(self._entity, 'stonehearth:growing', self, self._on_grow_period)
   end

   self._megacrop_description = self._json.megacrop_description or stonehearth.constants.farming.DEFAULT_MEGACROP_DESCRIPTION
   self._megacrop_model_variant = self._json.megacrop_model_variant
   self._megacrop_change_scale = self._json.megacrop_change_scale
   if self._megacrop_change_scale == nil then
      self._megacrop_change_scale = stonehearth.constants.farming.DEFAULT_MEGACROP_SCALE
   end
   self._auto_harvest = self._json.auto_harvest
   self._post_harvest_stage = self._json.post_harvest_stage

   if not self._sv._megacrop_chance then
      self._sv._megacrop_chance = self._json.megacrop_chance or stonehearth.constants.farming.BASE_MEGACROP_CHANCE
   end
end

function CropComponent:post_activate()
   -- put this in post_activate so everything else has a chance to get up to speed
   -- also, if this _on_grow_period happens and makes it harvestable, it will trigger _notify_harvestable so we don't need to do that
   local did_restore_grow_event = false
   if self._is_restore then
      local growing_component = self._entity:get_component('stonehearth:growing')
      if growing_component then
         local stage = growing_component:get_current_stage_name()
         if stage ~= self._sv.stage then
            -- If stages are mismatched somehow, fix it up.
            -- There was a carrot crop whose stage got mixed up somehow
            -- Likely due to a growing component listener firing when listener was not yet registered -yshan 3/2/2016
            local e = {}
            e.stage = stage
            e.finished = growing_component:is_finished()
            self:_on_grow_period(e)
            did_restore_grow_event = true
         end
      end
   end

   if not did_restore_grow_event and self._sv.harvestable and self._sv._field then
      self:_notify_harvestable()
   end
end

-- when having a crop mature into a different entity, copy its data
function CropComponent:copy_data(crop_comp)
   local field = crop_comp:get_field()
   local x, y = crop_comp:get_field_offset()
   self:set_field(field, x, y)
   self:set_destroy_on_crop_change(crop_comp:get_destroy_on_crop_change())
end

function CropComponent:set_field(field, x, y)
   self._sv._field = field
   self._sv._field_offset_x = x
   self._sv._field_offset_y = y
end

function CropComponent:set_destroy_on_crop_change(value)
   self._sv._destroy_on_crop_change = value
end

function CropComponent:get_destroy_on_crop_change()
   return self._sv._destroy_on_crop_change
end

function CropComponent:get_field()
   return self._sv._field
end

function CropComponent:get_field_offset()
   return self._sv._field_offset_x, self._sv._field_offset_y
end

function CropComponent:get_product()
   return self._sv.product
end

function CropComponent:get_post_harvest_stage()
   return self._post_harvest_stage
end

function CropComponent:get_stacks_per_harvest()
   return self._stacks_per_harvest
end

function CropComponent:update_post_harvest_crop()
   if self._sv._field then
      self._sv._field:update_post_harvest_crop(self._sv._field_offset_x, self._sv._field_offset_y, self._entity)
   end
end

function CropComponent:destroy()
   if self._sv._field then
      self._sv._field:notify_crop_destroyed(self._sv._field_offset_x, self._sv._field_offset_y)
      self._sv._field = nil
   end
   if self._growing_listener then
      self._growing_listener:destroy()
      self._growing_listener = nil
   end

   if self._game_loaded_listener then
      self._game_loaded_listener:destroy()
      self._game_loaded_listener = nil
   end
end

--- As we grow, change the resources we yield and, if appropriate, command harvest
function CropComponent:_on_grow_period(e)
   self._sv.stage = e.stage
   if e.stage then
      local resource_pairing_uri = self._resource_pairings[self._sv.stage]
      self._sv.product = resource_pairing_uri ~= '' and resource_pairing_uri or nil

      if self._sv.stage == self._harvest_threshhold and self._sv._field then
         self._sv.harvestable = true
         self:_became_harvestable()
      elseif not resource_pairing_uri and self._sv.harvestable then
         -- when resetting to an earlier stage, make it no longer harvestable
         self._sv.harvestable = false
         self:_notify_unharvestable()
      end
   end
   if e.finished and not self._post_harvest_stage then
      --TODO: is growth ever really complete? Design the difference between "can't continue" and "growth complete"
      if self._growing_listener then
         self._growing_listener:destroy()
         self._growing_listener = nil
      end
   end
   self.__saved_variables:mark_changed()
end

--- Returns true if it's time to harvest, false otherwise
function CropComponent:is_harvestable()
   return self._sv.harvestable
end

function CropComponent:_notify_harvestable()
   radiant.assert(self._sv._field, 'crop %s has no field!', self._entity)
   self._sv._field:notify_crop_harvestable(self._sv._field_offset_x, self._sv._field_offset_y)
   -- try to auto-harvest the crop
   self._sv._field:try_harvest_crop(nil, self._sv._field_offset_x, self._sv._field_offset_y, nil, self._auto_harvest)
end

function CropComponent:_notify_unharvestable()
   radiant.assert(self._sv._field, 'crop %s has no field!', self._entity)
   self._sv._field:notify_crop_unharvestable(self._sv._field_offset_x, self._sv._field_offset_y)
end

-- separate this out into its own function so it's easier to modify
function CropComponent:_became_harvestable()
   if self._sv._consider_megacrop and self._sv._is_megacrop == nil then
      if rng:get_real(0, 1) < self._sv._megacrop_chance then
         self:_set_megacrop()
      end
   end

   self:_notify_harvestable()
end

function CropComponent:set_fertilized()
   -- not really used at the moment, maybe refactor the fertilize ai to do more of it in here
end

function CropComponent:set_consider_megacrop()
   if not self._sv._consider_megacrop then
      self._sv._consider_megacrop = true
      --self.__saved_variables:mark_changed()
   end
end

function CropComponent:apply_megacrop_chance_multiplier(multiplier)
   if multiplier ~= 1 and self._sv._megacrop_chance ~= 0 then
      self._sv._megacrop_chance = self._sv._megacrop_chance * multiplier
      --self.__saved_variables:mark_changed()
   end
end

function CropComponent:is_megacrop()
   return self._sv._is_megacrop
end

function CropComponent:_set_megacrop()
   self._sv._is_megacrop = true
   
   if self._megacrop_description then
      radiant.entities.set_description(self._entity, self._megacrop_description)
   end

   local render_info = self._entity:get_component('render_info')
   if self._megacrop_model_variant then
      render_info:set_model_variant(self._megacrop_model_variant)
   end
   if self._megacrop_change_scale then
      render_info:set_scale(render_info:get_scale() * (self._megacrop_change_scale + rng:get_real(-0.05, 0.05)))
   end

   --self.__saved_variables:mark_changed()
end

function CropComponent:get_harvest_items(owner, num_stacks)
   local primary_item
   local items = {}

   owner = owner or self._entity
   local product_uri = self:get_product()
   local quality = radiant.entities.get_item_quality(self._entity)
   local megacrop_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:megacrop') or {}
   
   if self:is_megacrop() then
      local num_to_spawn = megacrop_data.num_to_spawn or 3
      local other_items = megacrop_data.other_items
      local pickup_new = other_items and megacrop_data.pickup_new ~= nil and megacrop_data.pickup_new
      
      -- spawn "other" items first, so we can easily separate the first one
      if other_items then
         for uri, count in pairs(other_items) do
            for i = 1, count do
               local item = self:_create_item(owner, uri, quality)
               if item then
                  if not primary_item then
                     primary_item = item
                  else
                     items[item:get_id()] = item
                  end
               end
            end
         end
      end

      -- spawn more of the product
      for i = 1, num_to_spawn do
         local item = self:_create_item(owner, product_uri, quality, 1, true)
         if item then
            items[item:get_id()] = item
         end
      end
   end

   if not primary_item and (not self:is_megacrop() or not megacrop_data.return_immediately) then
      primary_item = self:_create_item(owner, product_uri, quality, num_stacks)
   end

   return primary_item, items
end

function CropComponent:_create_item(player_id, uri, crop_quality, num_stacks, max_stacks)
   if not uri then
      return
   end

   local product = radiant.entities.create_entity(uri, { owner = player_id })
   
   if crop_quality > 1 then
      item_quality_lib.copy_quality(self._entity, product)
   end

   local entity_forms = product:get_component('stonehearth:entity_forms')

   --If there is an entity_forms component, then you want to put the iconic version
   --in the farmer's arms, not the actual entity (ie, if we had a chair crop)
   --This also prevents the item component from being added to the full sized versions of things.
   if entity_forms then
      local iconic = entity_forms:get_iconic_entity()
      if iconic then
         product = iconic
      end
   end

   local stacks_component = product:get_component('stonehearth:stacks')
   if stacks_component then
      stacks_component:set_stacks((max_stacks and stacks_component:get_max_stacks()) or num_stacks or 1)
   end

   return product
end

return CropComponent
