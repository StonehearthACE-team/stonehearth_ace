local GrowingComponent = require 'stonehearth.components.growing.growing_component'
local AceGrowingComponent = class()
local log = radiant.log.create_logger('growing')

AceGrowingComponent._ace_old_restore = GrowingComponent.restore
function AceGrowingComponent:restore()
   self:_ace_old_restore()

   if self._sv.growth_timer then
      self._sv._growth_timer = self._sv.growth_timer
      self._sv.growth_timer = nil
   end
   self._restore_uri = self._entity:get_uri()
end

AceGrowingComponent._ace_old_activate = GrowingComponent.activate
function AceGrowingComponent:activate()
	local json = radiant.entities.get_json(self)
   self._require_flooding = json and json.require_flooding or false

   if not self._sv.custom_growth_time_multiplier then
      self._sv.custom_growth_time_multiplier = 1
   end

   if not self._sv._environmental_growth_time_modifier then
      self._sv._environmental_growth_time_modifier = 1
   end

   if not self._sv._current_growth_recalculate_progress then
      self._sv._current_growth_recalculate_progress = 0
   end

   if self._sv._enabled == nil then
      self._sv._enabled = true
   end

   self._temp_growth_time_multiplier = 1

	self:_ace_old_activate()
end

AceGrowingComponent._ace_old_post_activate = GrowingComponent.post_activate
function AceGrowingComponent:post_activate()
   -- growth stages are expressed with unit_info display_name, but we want to lock custom_names for these entities
   -- a growing entity could potentially transform on reloading into a different entity, so check for validity
   if self._entity and self._entity:is_valid() then
      self._entity:add_component('stonehearth:unit_info'):lock('stonehearth:growing')
   else
      log:error('entity with uri %s is invalid on post_activate, cannot lock unit_info component', self._restore_uri)
   end
   self._restore_uri = nil

   if self._ace_old_post_activate then
      self:_ace_old_post_activate()
   end
end

function AceGrowingComponent:set_growth_stage(stage)
   stage = math.max(1, math.min(stage, #self._growth_stages))
   self._sv.current_growth_stage = stage
   self._sv._current_growth_recalculate_progress = 0
   self._sv.growth_attempts = 0
   self.__saved_variables:mark_changed()

   self:_apply_current_stage()
   self:_set_growth_timer()
   
   radiant.events.trigger(self._entity, 'stonehearth:growing', {
      entity = self._entity,
      stage = self:get_current_stage_name(),
      finished = self:is_finished(),
   })
end

function AceGrowingComponent:set_environmental_growth_time_modifier(modifier)
	if modifier ~= self._sv._environmental_growth_time_modifier then
      self._sv._environmental_growth_time_modifier = modifier
      self:_recalculate_duration()
		--self.__saved_variables:mark_changed()
   end
end

function AceGrowingComponent:set_flooded(flooded)
   -- depending on the crop settings, we may disable growth
   self._sv._is_flooded = flooded
   self._sv._enabled = not self._require_flooding or flooded

   if self._sv._enabled then
      self:_start()
   else
      self:_recalculate_duration(true)
   end
   --self.__saved_variables:mark_changed()
end

function AceGrowingComponent:is_flooded()
   return self._sv._is_flooded
end

function AceGrowingComponent:modify_custom_growth_time_multiplier(multiplier)
   if multiplier ~= 1 then
      self:set_custom_growth_time_multiplier(self._sv.custom_growth_time_multiplier * multiplier)
   end
end

function AceGrowingComponent:set_custom_growth_time_multiplier(multiplier)
   if self._sv.custom_growth_time_multiplier ~= multiplier then
      self._sv.custom_growth_time_multiplier = multiplier
      self:_recalculate_duration()
		self.__saved_variables:mark_changed()
   end
end

-- used for temporary (e.g., AI-applied) modifiers
function AceGrowingComponent:modify_temp_growth_time_multiplier(multiplier)
   if multiplier ~= 1 then
      self._temp_growth_time_multiplier = self._temp_growth_time_multiplier * multiplier
      self:_recalculate_duration()
   end
end

function AceGrowingComponent:_recalculate_duration(skip_creation)
   if self._sv._growth_timer and self._sv._growth_timer.get_duration then
		local old_duration = self._sv._growth_timer:get_duration()
		local old_expire_time = self._sv._growth_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
	  
		local old_progress = self._sv._current_growth_recalculate_progress
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
      self._sv._current_growth_recalculate_progress = old_progress + new_progress
      self._sv._growth_timer:destroy()

      if not skip_creation then 
         self:_set_growth_timer()
      end
	end
end

function AceGrowingComponent:_calculate_growth_period(growth_period)
	if not growth_period then
		growth_period = self:_get_base_growth_period()
   end
   -- we don't want the biome/weather modifiers, those should be handled with sunlight/humidity values
   -- we only care about the vitality town bonus (and any other bonuses that may get modded in)
   local scaled_growth_period = stonehearth.town:calculate_town_bonuses_growth_period(self._entity:get_player_id(), growth_period)
         * self._sv.custom_growth_time_multiplier * self._temp_growth_time_multiplier
   
   if self._sv._environmental_growth_time_modifier then
		scaled_growth_period = scaled_growth_period * self._sv._environmental_growth_time_modifier
   end

	return scaled_growth_period
end

function AceGrowingComponent:_set_growth_timer()
   if self._sv._growth_timer then
      self._sv._growth_timer:destroy()
      self._sv._growth_timer = nil
   end
   if not self:is_finished() then
      local growth_period = self:_calculate_growth_period()
      local time_remaining = math.max(0, growth_period * (1 - self._sv._current_growth_recalculate_progress))
      local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
      self._sv._growth_timer = stonehearth.calendar:set_persistent_timer("GrowingComponent grow_callback", scaled_time_remaining, radiant.bind(self, '_grow'))
   end
end

AceGrowingComponent._ace_old__grow = GrowingComponent._grow
function AceGrowingComponent:_grow()
   if not radiant.entities.is_entity_town_suspended(self._entity) then
      self:_ace_old__grow()
   else
      self:_set_growth_timer()
   end

	self._sv._current_growth_recalculate_progress = 0
end

-- override these two functions to prepend growth_timer with an underscore
function AceGrowingComponent:_start()
   if not self._sv._growth_timer and self._sv._enabled then
      self:_set_growth_timer()
   end
   --Make our current model look like the saved model
   self:_apply_current_stage()
end

function AceGrowingComponent:stop_growing()
   if self._sv._growth_timer then
      self._sv._growth_timer:destroy()
      self._sv._growth_timer = nil
   end
   --self.__saved_variables:mark_changed()
end

return AceGrowingComponent
