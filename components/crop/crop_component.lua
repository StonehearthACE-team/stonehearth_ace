--[[
   Every time the crop grows, update its resource node resource. More mature crops
   yield better resources.

   Paul: overriding this whole file because they put component data accessors in the initialize function
      and we can't override the initialize function (it gets cached for existing entities before our monkey patch runs)
]]
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
end

function CropComponent:restore()
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
      end
   end

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

   self._megacrop_description = self._json.megacrop_description or stonehearth.constants.farming.default_megacrop_description
   self._megacrop_model_variant = self._json.megacrop_model_variant
   self._auto_harvest = self._json.auto_harvest
   self._post_harvest_stage = self._json.post_harvest_stage

   if not self._sv._megacrop_chance then
      self._sv._megacrop_chance = self._json.megacrop_chance or stonehearth.constants.farming.BASE_MEGACROP_CHANCE
   end
end

function CropComponent:post_activate()
   if self._sv.harvestable and self._sv._field then
      self:_notify_harvestable()
   end
end

function CropComponent:set_field(field, x, y)
   self._sv._field = field
   self._sv._field_offset_x = x
   self._sv._field_offset_y = y
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
      if resource_pairing_uri then
         if resource_pairing_uri == "" then
            resource_pairing_uri = nil
         end
         self._sv.product = resource_pairing_uri
      end
      if self._sv.stage == self._harvest_threshhold and self._sv._field then
         self._sv.harvestable = true
         self:_became_harvestable()
      else
         -- when resetting to an earlier stage, make it no longer harvestable
         if self._sv.harvestable then
            self._sv.harvestable = false
            self:_notify_unharvestable()
         end
      end
   end
   if e.finished then
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

   if self._auto_harvest then
      -- auto-harvest the crop
      if self._sv._field then
         self._sv._field:auto_harvest_crop(self._auto_harvest, self._sv._field_offset_x, self._sv._field_offset_y)
      end
   end
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
      self._entity:get_component('render_info'):set_model_variant(self._megacrop_model_variant)
   end
   render_info:set_scale(render_info:get_scale() * (2 + rng:get_real(-0.05, 0.05)))

   --self.__saved_variables:mark_changed()
end

return CropComponent
