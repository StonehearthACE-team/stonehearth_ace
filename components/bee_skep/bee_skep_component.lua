local rng = _radiant.math.get_default_rng()
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local log = radiant.log.create_logger('bee_skep_component')
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local constants = require 'stonehearth.constants'
local bee_skep_constants = constants.bee_skeps

local SKEP_BUFF = 'stonehearth_ace:buffs:bee_skep'
local POLLINATION_BUFFS = {
         'stonehearth_ace:buffs:pollinated:pollination:up',
         'stonehearth_ace:buffs:pollinated:pollination:neutral',
         'stonehearth_ace:buffs:pollinated:pollination:down'
      }
local POLLINATED_BUFF = 'stonehearth_ace:buffs:pollinated'
local POLLINATED_CROP_BUFF = 'stonehearth_ace:buffs:pollinated:crop'
local POLLINATED_PLANTER_BUFF = 'stonehearth_ace:buffs:tended_planter:pollinated'

local BeeSkepComponent = class()

function BeeSkepComponent:initialize()
   self._sv._score = 0
end

function BeeSkepComponent:activate()
   self._json = radiant.entities.get_json(self)

   self._update_period = self._json and self._json.update_period or bee_skep_constants.UPDATE_PERIOD
   self._range = self._json and self._json.range or bee_skep_constants.RANGE
   self._max_pollinations = self._json and self._json.max_pollinations or bee_skep_constants.MAX_POLLINATIONS_PER_UPDATE
   self._score_per_pollination = self._json and self._json.score_per_pollination or bee_skep_constants.SCORE_PER_POLLINATION
   self._improvement_chance = self._json and self._json.improvement_chance or bee_skep_constants.IMPROVEMENT_CHANCE
   self._score_loss = self._json and self._json.score_loss or bee_skep_constants.SCORE_LOSS_PER_FAILED_UPDATE
   self._score_for_quality_upgrade = self._json and self._json.score_for_quality_upgrade or bee_skep_constants.SCORE_FOR_QUALITY_UPGRADE
   self._max_score = self._json and self._json.max_score or bee_skep_constants.MAX_SCORE

   if not self._search_cube then
      self._search_cube = Cube3(Point3.zero):inflated(Point3(self._range, self._range, self._range))
   end
end

function BeeSkepComponent:post_activate()
   if not self._sv._initialized then
      local current_quality = radiant.entities.get_item_quality(self._entity)
      if current_quality ~= 1 then
         log:info('bee skep %s already has higher quality %s, giving it a starting score', self._entity, current_quality)
         self._sv._score = self._score_for_quality_upgrade[math.max(1, math.floor(current_quality - 1))]
         self._sv._initialized = true
      else
         self._item_quality_listener = radiant.events.listen(self._entity, 'stonehearth:item_quality_added', 
            function(quality)
               self:_destroy_quality_listener()
               log:info('bee skep %s getting initialized with quality %s, giving it a starting score', self._entity, quality)
               self._sv._score = self._score_for_quality_upgrade[math.max(1, math.floor(quality - 1))]
               self._sv._initialized = true
            end)
      end
   end

   self:_seasonality_check()

   if self._is_restore then
      self:_score_check()
   end

   if not self._season_change_listener then
      self:_create_seasonal_listener()
   end
end

function BeeSkepComponent:restore()
   self._is_restore = true
end

function BeeSkepComponent:_create_seasonal_listener()
   -- log:info('creating bee skep season change listener')
   self._season_change_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
      self:_seasonality_check()
   end)
end

function BeeSkepComponent:_create_timers()
   -- log:info('creating bee skep timer')
   self._sv._update_timer = stonehearth.calendar:set_persistent_interval('bee skep update timer', self._update_period, function()
      self:_update()
   end)
end

function BeeSkepComponent:_update()
   -- Don't update if paused (this shouldn't even run)
   if self._sv._paused then
      log:info('bee skep %s is paused and will not update!', self._entity)
      return
   end

   -- a skep that isn't placed or valid for w/e reason shouldn't update
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location or not self._entity:is_valid() then
      log:error('bee skep %s is not valid!', self._entity)
      return
   end

   -- if the skep is covered/sheltered, it should automatically fail updating. Add some to the skep's location.y to prevent its shelter check from colliding with itself (this check is so stupid...)
   if stonehearth.terrain:is_sheltered(location + (Point3.unit_y * 3)) then
      log:info('bee skep %s is sheltered and loses score!', self._entity)
      self._sv._score = math.max(0, (self._sv._score - self._score_loss))
      self:_score_check()
      return
   end

   local pollinations = rng:get_int(1, self._max_pollinations)
   local potential_targets = {}
   local target_entities = {}
   potential_targets = radiant.terrain.get_entities_in_cube(self._search_cube:translated(location), function(entity)
      return self:_can_pollinate(entity)
   end)
   
   local amount = 0
   for _ in pairs(potential_targets) do
      amount = amount + 1
   end
   log:debug('bee skep %s updating status buff, %s potential targets detected', self._entity, amount)
   self:_update_status_buff(amount)

   while next(potential_targets) and #target_entities < pollinations do
      local keys = {}
      for id in pairs(potential_targets) do
         table.insert(keys, id)
      end

      local random_key = keys[rng:get_int(1, #keys)]
      local target = potential_targets[random_key]

      log:debug('bee skep %s target %s added!', self._entity, target)
      table.insert(target_entities, target)

      potential_targets[random_key] = nil
   end

   if next(target_entities) then
      for _, target in ipairs(target_entities) do
         self:_pollinate_target(target)
      end
      log:info('bee skep %s pollinated %s targets!', self._entity, tostring(#target_entities))
      self:_score_check()
   else
      log:info('bee skep %s could not find any targets!', self._entity)
      self._sv._score = math.max(0, (self._sv._score - self._score_loss))
      self:_score_check()
   end
end

function BeeSkepComponent:_can_pollinate(target)
   local herbalist_planter = target:get_component('stonehearth_ace:herbalist_planter')
   if herbalist_planter then
      log:debug('bee skep target %s is a herbalist planter', target)
      return herbalist_planter:is_pollinatable() and herbalist_planter:is_tendable(nil, true)
   end

   local crop = target:get_component('stonehearth:crop')
   local is_plant = radiant.entities.get_category(target) == 'plants'

   if (crop and not radiant.entities.has_buff(target, POLLINATED_CROP_BUFF)) or (is_plant and not radiant.entities.has_buff(target, POLLINATED_BUFF)) then
      log:debug('bee skep target %s is a crop or plant', target)
      return not radiant.entities.is_material(target, 'no_pollination')
   end

   return false
end

function BeeSkepComponent:_pollinate_target(target)
   local current_quality = radiant.entities.get_item_quality(self._entity)
   local herbalist_planter = target:get_component('stonehearth_ace:herbalist_planter')
   local crop = target:get_component('stonehearth:crop')
   local expected_score = self._score_per_pollination

   if herbalist_planter then
      -- Handle a herbalist planter target
      herbalist_planter:tend_to_crop(nil, current_quality)
      radiant.entities.add_buff(target, POLLINATED_PLANTER_BUFF, {
         source = self._entity,
         source_player = radiant.entities.get_player_id(self._entity)
      })

      -- Give extra score for larger planters
      if herbalist_planter._sv.num_products ~= 1 then
         expected_score = math.min(4, (math.ceil(herbalist_planter._sv.num_products / 2)))
      end
   elseif crop then
      -- Handle a crop target
      if rng:get_real(0, 1) <= self._improvement_chance[current_quality] then
         item_quality_lib.apply_quality(target, radiant.entities.get_item_quality(target) + 1, {
            max_quality = item_quality_lib.get_max_random_quality(self._entity:get_player_id())
         })
         -- Give extra score for succeeding
         expected_score = expected_score + 1
      end
      radiant.entities.add_buff(target, POLLINATED_CROP_BUFF, {
         source = self._entity,
         source_player = radiant.entities.get_player_id(self._entity)
      })
   else
      -- Probably a generic or wild plant       
      if rng:get_real(0, 1) <= self._improvement_chance[current_quality] then
         item_quality_lib.apply_quality(target, radiant.entities.get_item_quality(target) + 1, {
            max_quality = item_quality_lib.get_max_random_quality(self._entity:get_player_id())
         })
         -- Give extra score for succeeding
         expected_score = expected_score + 1
      end
      radiant.entities.add_buff(target, POLLINATED_BUFF, {
         source = self._entity,
         source_player = radiant.entities.get_player_id(self._entity)
      })
   end

   -- Add score
   self._sv._score = math.min(self._max_score, (self._sv._score + expected_score))
end

function BeeSkepComponent:_score_check()
   local current_quality = radiant.entities.get_item_quality(self._entity)
   local expected_quality = 1
   for quality, score in ipairs(self._score_for_quality_upgrade) do
      if self._sv._score >= score then
         expected_quality = quality + 1
      end
   end

   if current_quality ~= expected_quality then
      self:_destroy_quality_listener()
      self._sv._initialized = true
      item_quality_lib.apply_quality(self._entity, expected_quality, {
         allow_lower = true,
         max_quality = item_quality_lib.get_max_random_quality(self._entity:get_player_id())
      })
   end
end

function BeeSkepComponent:_seasonality_check()
   if radiant.entities.has_buff(self._entity, SKEP_BUFF) then
      self._sv._paused = false
      if not self._sv._update_timer then
         self:_create_timers()
      end
   else
      self._sv._paused = true
      self:_update_status_buff()
      if self._sv._update_timer then
         self:_destroy_timers()
      end
   end
end

function BeeSkepComponent:_update_status_buff(amount)
    local active_buff

    if not self._sv._paused and amount then
        if amount > 4 * self._max_pollinations then
            active_buff = POLLINATION_BUFFS[1]
        elseif amount > 0 then
            active_buff = POLLINATION_BUFFS[2]
        elseif amount == 0 then
            active_buff = POLLINATION_BUFFS[3]
        end
    end

    for _, buff in ipairs(POLLINATION_BUFFS) do
        if buff == active_buff then
            radiant.entities.add_buff(self._entity, buff)
        else
            radiant.entities.remove_buff(self._entity, buff)
        end
    end
end

function BeeSkepComponent:destroy()
   self:_destroy_timers()
   self:_destroy_quality_listener()
   self:_destroy_seasonal_listener()
   self._sv._score = nil
end

function BeeSkepComponent:_destroy_quality_listener()
   if self._item_quality_listener then
      self._item_quality_listener:destroy()
      self._item_quality_listener = nil
   end
end

function BeeSkepComponent:_destroy_seasonal_listener()
   if self._season_change_listener then
      self._season_change_listener:destroy()
      self._season_change_listener = nil
   end
end

function BeeSkepComponent:_destroy_timers()
   if self._sv._update_timer then
      self._sv._update_timer:destroy()
      self._sv._update_timer = nil
   end
end

return BeeSkepComponent
