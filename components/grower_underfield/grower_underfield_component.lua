--[[
   Component for a underfield that grows undercrops
]]

local rng = _radiant.math.get_default_rng()
local Cube3 = _radiant.csg.Cube3
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('grower_underfield')
local rng = _radiant.math.get_default_rng()

local GrowerUnderfieldComponent = class()

local VERSIONS = {
   ZERO = 0,
   BFS_PLANTING = 1,
   SUBSTRATE_PLOT_RENDERING = 2,
   FIXUP_INCONSISTENT_UNDERFIELD_LAYERS = 3,
   ADD_UNDERFIELD_TO_UNDERCROPS = 4
}

local SUBSTRATE_UNDERCROP_ID = 'substrate'

function GrowerUnderfieldComponent:get_version()
   return VERSIONS.ADD_UNDERFIELD_TO_UNDERCROPS
end

function GrowerUnderfieldComponent:initialize()
   -- Declare all the sv variables
   self._sv._soil_layer = nil
   self._sv._plantable_layer = nil
   self._sv._harvestable_layer = nil

   self._sv.size = nil -- Needs to remote to client for the grower underfield renderer
   self._sv.contents = {} -- Needs to remote to the client for grower underfield renderer

   self._sv.general_fertility = 0
   self._sv.current_undercrop_alias = nil -- remoted to client for the UI
   self._sv.current_undercrop_details = nil
   self._sv.has_set_undercrop = false -- remoted to client for the UI
   self._sv.num_undercrops = 0

   
   self._workers = {}  -- growers currently working this underfield
end

function GrowerUnderfieldComponent:create()
   -- Create the farm layers that will be used for bfs
   self._sv.size = Point2.zero -- This must be initialized to 0,0 so the renderer of this component can work

   -- Sigh, since entities can be destroyed in any order, these guys can go before us, and then we'd have a nil exception
   self._sv._soil_layer = self:_create_underfield_layer('stonehearth_ace:mountain_folk:grower:underfield_layer:tillable')
   self._sv._plantable_layer = self:_create_underfield_layer('stonehearth_ace:mountain_folk:grower:underfield_layer:plantable')
   self._sv._harvestable_layer = self:_create_underfield_layer('stonehearth_ace:mountain_folk:grower:underfield_layer:harvestable')

   local min_fertility = stonehearth.constants.soil_fertility.MIN
   local max_fertility = stonehearth.constants.soil_fertility.MAX
   self._sv.general_fertility = rng:get_int(min_fertility, max_fertility)   --TODO; get from global service

   -- always start out substrate
   self._sv.current_undercrop_alias = SUBSTRATE_UNDERCROP_ID
   self._sv.current_undercrop_details = stonehearth_ace.underfarming:get_undercrop_details(SUBSTRATE_UNDERCROP_ID)
   self._sv.has_set_undercrop = false
end

function GrowerUnderfieldComponent:restore()
   self._location = radiant.entities.get_world_grid_location(self._entity)
   if self._needs_plantable_layer_placement then
      radiant.terrain.place_entity(self._sv._plantable_layer, self._location)
      self:_update_plantable_layer()
   end
   if self._needs_substrate_plot_upgrade then
      self:fixup_substrate_plots()
      self._needs_substrate_plot_upgrade = false
   end

   if self._needs_layer_validation then
      self:_validate_layers()
      self._needs_layer_validation = false
   end

   self._sv._soil_layer:get_component('destination')
                        :set_reserved(_radiant.sim.alloc_region3()) -- xxx: clear the existing one from cpp land!
                        :set_auto_update_adjacent(true)

   self._sv._harvestable_layer:get_component('destination')
                        :set_reserved(_radiant.sim.alloc_region3()) -- xxx: clear the existing one from cpp land!
                        :set_auto_update_adjacent(true)

   self._sv._plantable_layer:get_component('destination')
                        :set_reserved(_radiant.sim.alloc_region3()) -- xxx: clear the existing one from cpp land!
                        :set_auto_update_adjacent(true)
end

function GrowerUnderfieldComponent:activate()
   self._location = radiant.entities.get_world_grid_location(self._entity)
   self._underfield_listeners = {}
   table.insert(self._underfield_listeners, radiant.events.listen(self._sv._soil_layer, 'radiant:entity:pre_destroy', self, self._on_underfield_layer_destroyed))
   table.insert(self._underfield_listeners, radiant.events.listen(self._sv._harvestable_layer, 'radiant:entity:pre_destroy', self, self._on_underfield_layer_destroyed))
   table.insert(self._underfield_listeners, radiant.events.listen(self._sv._plantable_layer, 'radiant:entity:pre_destroy', self, self._on_underfield_layer_destroyed))

   self._player_id_trace = self._entity:trace_player_id('grower underfield component tracking player_id')
      :on_changed(function()
            stonehearth.ai:reconsider_entity(self._entity, 'grower underfield player id changed')
            self:_update_score()
         end)

   self:_update_score()
end

function GrowerUnderfieldComponent:_on_underfield_layer_destroyed(e)
   -- Something bad has happened! just destroy ourselves because we can't recover from a layer being destroyed
   if self._underfield_listeners then
      log:detail('A grower underfield layer %s has been destroyed! destroying the entire underfield %s because there is no recovery. This is normal in autotests.', e.entity, self._entity)
      self:_on_destroy()
      radiant.entities.destroy_entity(self._entity)
   end
end

function GrowerUnderfieldComponent:_create_underfield_layer(uri)
   local layer = radiant.entities.create_entity(uri, { owner = self._entity })
   layer:add_component('destination')
                              :set_region(_radiant.sim.alloc_region3())
                              :set_reserved(_radiant.sim.alloc_region3())
                              :set_auto_update_adjacent(true)

   layer:add_component('stonehearth_ace:grower_underfield_layer')
                                 :set_grower_underfield(self)
   return layer
end

function GrowerUnderfieldComponent:get_bounds()
   return self:_get_bounds()
end

function GrowerUnderfieldComponent:_get_bounds()
   local size = self._sv.size
   local bounds = Cube3(Point3(0, 0, 0), Point3(size.x, 1, size.y))
   return bounds
end

function GrowerUnderfieldComponent:on_underfield_created(town, size)
   -- Called from the farming service when the underfield is first created
   -- This will update the soil layer to say this entire underfield needs
   -- to be tilled.
   self._location = radiant.entities.get_world_grid_location(self._entity)
   self._sv.size = Point2(size.x, size.y)

   radiant.terrain.place_entity(self._sv._soil_layer, self._location)
   radiant.terrain.place_entity(self._sv._plantable_layer, self._location)
   radiant.terrain.place_entity(self._sv._harvestable_layer, self._location)

   for x=1, size.x do
      table.insert(self._sv.contents, {})
   end

   local soil_layer = self._sv._soil_layer
   local soil_layer_region = soil_layer:get_component('destination')
                                :get_region()

   -- Modify the soil layer to have the bounds of our cube
   soil_layer_region:modify(function(cursor)
      cursor:clear()
      cursor:add_cube(self:_get_bounds())
   end)

   town:register_farm(self._entity)

   self.__saved_variables:mark_changed()
end

function GrowerUnderfieldComponent:notify_score_changed()
   if not self._score_dirty then
      self._score_dirty = true
      self._gameloop_listener = stonehearth.calendar:set_timer("update grower underfield score", '15m', function()
         self._gameloop_listener = nil
         self:_update_score()
      end)
   end
end

function GrowerUnderfieldComponent:_update_score()
   local value_of_each_undercrop = 0
   self._score_dirty = false

   if not self._sv.current_undercrop_alias or self:_is_substrate() then
      -- No undercrop set. Cannot have net worth
      stonehearth.score:change_score(self._entity, 'net_worth', 'agriculture', 0)
      return
   end

   local net_worth = radiant.entities.get_net_worth(self._sv.current_undercrop_alias)
   if net_worth then
      value_of_each_undercrop = net_worth
   end

   if value_of_each_undercrop <= 0 then
      -- No value for undercrops. Cannot have net worth
      stonehearth.score:change_score(self._entity, 'net_worth', 'agriculture', 0)
      return
   end

   local underfield_size = self._sv.size
   local underfield_contents = self._sv.contents
   local score = 0

   for x=1, underfield_size.x do
      for y=1, underfield_size.y do
         local substrate_plot = underfield_contents[x][y]
         if substrate_plot then
            local undercrop = substrate_plot.contents
            if undercrop and undercrop:is_valid() then
               score = score + value_of_each_undercrop
            end
         end
      end
   end
   score = radiant.math.round(score)
   stonehearth.score:change_score(self._entity, 'net_worth', 'agriculture', score)
end

--Tries 1000 times to get a random undercrop from the underfield, or returns first random undercrop
function GrowerUnderfieldComponent:get_random_undercrop()
   if self._sv.num_undercrops <= 0 then
      return nil
   end

   local underfield_size = self._sv.size
   local underfield_contents = self._sv.contents
   local tries = 0
   local max_tries = 1000

   while tries < max_tries do 
      local random_x = rng:get_int(1, underfield_size.x)
      local random_y = rng:get_int(1, underfield_size.y)
      local substrate_plot = underfield_contents[random_x][random_y]
      if substrate_plot then
         local undercrop = substrate_plot.contents
         if undercrop and undercrop:is_valid() then
            return undercrop
         end
      end
      tries = tries + 1
   end

   --Ok, random didn't work so return the first undercrop
   for x=1, underfield_size.x do
      for y=1, underfield_size.y do
         local substrate_plot = underfield_contents[x][y]
         if substrate_plot then
            --add a score for the plant if there's a plant in the dirt
            local undercrop = substrate_plot.contents
            if undercrop and undercrop:is_valid() then
               return undercrop
            end
         end
      end
   end

   --Ok that didn't work
   return nil
end


-- Call from the client to set the undercrop on this farm to a new undercrop
function GrowerUnderfieldComponent:set_undercrop(session, response, new_undercrop_id)
   self._sv.current_undercrop_alias = new_undercrop_id
   self._sv.current_undercrop_details = stonehearth_ace.underfarming:get_undercrop_details(new_undercrop_id)
   self._sv.has_set_undercrop = true

   self:_update_plantable_layer()

   self.__saved_variables:mark_changed()
   return true
end

function GrowerUnderfieldComponent:get_undercrop_details()
   return self._sv.current_undercrop_details
end

-- Called from the ai when a locatio nhas been tilled
function GrowerUnderfieldComponent:notify_till_location_finished(location)
   local offset = location - radiant.entities.get_world_grid_location(self._entity)
   local x = offset.x + 1
   local y = offset.z + 1
   local is_furrow = false
   if x % 2 == 0 then
      is_furrow = true
   end
   local substrate_plot = {
      is_furrow = is_furrow,
      x = x,
      y = y
   }

   --self:_create_tilled_dirt(location, offset.x + 1, offset.z + 1)
   self._sv.contents[offset.x + 1][offset.z + 1] = substrate_plot
   local local_fertility = rng:get_gaussian(self._sv.general_fertility, stonehearth.constants.soil_fertility.VARIATION)
   --local substrate_plot_component = substrate_plot:get_component('stonehearth:substrate_plot')

   -- Have to update the soil model to make the plot visible.
   --substrate_plot_component:update_soil_model(local_fertility, 50)

   local soil_layer = self._sv._soil_layer
   local soil_layer_region = soil_layer:get_component('destination')
                                :get_region()

   soil_layer_region:modify(function(cursor)
      cursor:subtract_point(offset)
   end)

   -- Add the region to the plantable region if necessary
   self:_try_mark_for_plant(substrate_plot)

   self.__saved_variables:mark_changed()
end

function GrowerUnderfieldComponent:_is_substrate()
   return self._sv.current_undercrop_alias == SUBSTRATE_UNDERCROP_ID
end

-- Iterates through the underfield and tries to mark all the dirt plots for planting if possible
function GrowerUnderfieldComponent:_update_plantable_layer()
   if not self:_is_substrate() then
      local underfield_size = self._sv.size
      local underfield_contents = self._sv.contents

      for x=1, underfield_size.x do
         for y=1, underfield_size.y do
            local substrate_plot = underfield_contents[x][y]
            if substrate_plot then
               self:_try_mark_for_plant(substrate_plot)
            end
         end
      end
   else
      self._sv._plantable_layer:get_component('destination')
                                   :set_region(_radiant.sim.alloc_region3())
   end
end

-- if the dirt plot is not furrow, add it to the plantable layer
function GrowerUnderfieldComponent:_try_mark_for_plant(substrate_plot)
   if not substrate_plot.is_furrow and not substrate_plot.contents and not self:_is_substrate() then
      -- Add the region to the plantable region
      local plantable_layer = self._sv._plantable_layer
      local destination = plantable_layer:get_component('destination')
      local plantable_layer_region = destination:get_region()

      plantable_layer_region:modify(function(cursor)
         cursor:add_point(Point3(substrate_plot.x - 1, 0, substrate_plot.y - 1))
      end)
   end
end

function GrowerUnderfieldComponent:plant_undercrop_at(x_offset, z_offset)
   local substrate_plot = self._sv.contents[x_offset][z_offset]
   radiant.assert(substrate_plot, "Trying to plant a undercrop on farm %s at (%s, %s) that has no dirt!", self._entity, x_offset, z_offset)
   local undercrop_type = self._sv.current_undercrop_alias

   if substrate_plot.contents ~= nil or not undercrop_type or self:_is_substrate() then
      return
   end

   local planted_entity = radiant.entities.create_entity(undercrop_type, { owner = self._entity })
   local position = Point3(self._location.x + x_offset - 1, self._location.y, self._location.z + z_offset - 1)
   radiant.terrain.place_entity_at_exact_location(planted_entity, position)
   substrate_plot.contents = planted_entity

   --If the planted entity is a undercrop, add a reference to the dirt it sits on.
   local undercrop_component = planted_entity:get_component('stonehearth_ace:undercrop')
   undercrop_component:set_underfield(self, substrate_plot.x, substrate_plot.y)

   self._sv.num_undercrops = self._sv.num_undercrops + 1

   self:notify_score_changed()
   self.__saved_variables:mark_changed()

   return planted_entity
end

function GrowerUnderfieldComponent:notify_undercrop_destroyed(x, z)
   if self._sv.contents == nil then
      --Sigh the undercrop component hangs on to us instead of the entity
      --if this component is already destroyed, don't process the notification -yshan
      return
   end
   local substrate_plot = self._sv.contents[x][z]
   if substrate_plot then
      substrate_plot.contents = nil

      local harvestable_layer = self._sv._harvestable_layer
      local harvestable_layer_region = harvestable_layer:get_component('destination')
                                          :get_region()
      harvestable_layer_region:modify(function(cursor)
         cursor:subtract_point(Point3(x - 1, 0, z - 1))
      end)

      self._sv.num_undercrops = self._sv.num_undercrops - 1

      self:notify_score_changed()
      self.__saved_variables:mark_changed()
      self:_try_mark_for_plant(substrate_plot)
   end
end

--True if there are actively undercrops on this underfield, false otherwise
function GrowerUnderfieldComponent:has_undercrops()
   return self._sv.num_undercrops > 0
end

function GrowerUnderfieldComponent:notify_plant_location_finished(location)
   local x_offset = location.x - self._location.x + 1
   local z_offset = location.z - self._location.z + 1
   self:plant_undercrop_at(x_offset, z_offset)

   local p = Point3(x_offset - 1, 0, z_offset - 1)
   local plantable_layer = self._sv._plantable_layer
   local plantable_layer_region = plantable_layer:get_component('destination')
                                :get_region()

   plantable_layer_region:modify(function(cursor)
      cursor:subtract_point(p)
   end)
   self.__saved_variables:mark_changed()
end

--- Given the underfield and dirt data, harvest the undercrop
function GrowerUnderfieldComponent:notify_undercrop_harvestable(x, z)
   local harvestable_layer = self._sv._harvestable_layer
   local harvestable_layer_region = harvestable_layer:get_component('destination')
                                       :get_region()
   harvestable_layer_region:modify(function(cursor)
      cursor:add_point(Point3(x - 1, 0, z - 1))
   end)
end

function GrowerUnderfieldComponent:undercrop_at(location)
   local x_offset = location.x - self._location.x + 1
   local z_offset = location.z - self._location.z + 1

   local substrate_plot = self._sv.contents[x_offset][z_offset]
   if substrate_plot then
      return substrate_plot.contents
   end
   return nil
end

function GrowerUnderfieldComponent:dirt_data_at(location)
   local x_offset = location.x - self._location.x + 1
   local z_offset = location.z - self._location.z + 1

   local substrate_plot = self._sv.contents[x_offset][z_offset]
   return substrate_plot
end

function GrowerUnderfieldComponent:_on_destroy()
   --Unlisten on all the underfield plot things
   local contents = self._sv.contents

   self._sv.contents = nil

   for x=1, self._sv.size.x do
      for y=1, self._sv.size.y do
         local substrate_plot = contents[x][y]
         if substrate_plot then
            -- destroys the dirt and undercrop entities
            -- if you don't want them to disappear immediately, then we need to figure out how they get removed from the world
            -- i.e. render the plant as decayed and implement a work task to clear rubble
            -- remember to undo ghost mode if you keep the entities around (see stockpile_renderer:destroy)
            if substrate_plot.contents then
               radiant.entities.destroy_entity(substrate_plot.contents)
               substrate_plot.contents = nil
            end
            contents[x][y] = nil
         end
      end
   end

   --Unregister from the town
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   town:unregister_farm(self._entity)


   self:_clear_underfield_listeners()

   radiant.entities.destroy_entity(self._sv._soil_layer)
   self._sv._soil_layer = nil

   radiant.entities.destroy_entity(self._sv._plantable_layer)
   self._sv._plantable_layer = nil

   radiant.entities.destroy_entity(self._sv._harvestable_layer)
   self._sv._harvestable_layer = nil

   if self._gameloop_listener then
      self._gameloop_listener:destroy()
      self._gameloop_listener = nil
   end
   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end
end

--- On destroy, destroy all the dirt plots and the layers
function GrowerUnderfieldComponent:destroy()
   if self._sv.contents ~= nil then
      self:_on_destroy()
   end
end

function GrowerUnderfieldComponent:_clear_underfield_listeners()
   if self._underfield_listeners then
      for i, listener in ipairs(self._underfield_listeners) do
         listener:destroy()
      end
      self._underfield_listeners = nil
   end
end

function GrowerUnderfieldComponent:debug_grow_all_undercrops(grow_count)
   for x=1, self._sv.size.x do
      for y=1, self._sv.size.y do
         local substrate_plot = self._sv.contents[x][y]
         if not substrate_plot then
            local is_furrow = false
            if x % 2 == 0 then
               is_furrow = true
            end
            local substrate_plot = {
               is_furrow = is_furrow,
               x = x,
               y = y
            }
            self._sv.contents[x][y] = substrate_plot
            if not is_furrow and grow_count ~= nil then
               local undercrop = self:plant_undercrop_at(x, y)
               local growing_component = undercrop:get_component('stonehearth:growing')
               for i=1, grow_count do
                  growing_component:_grow()
               end
            end
         end
      end
   end
   self._sv._soil_layer:get_component('destination')
                        :set_region(_radiant.sim.alloc_region3())

   self._sv._plantable_layer:get_component('destination')
                        :set_region(_radiant.sim.alloc_region3())
end

function GrowerUnderfieldComponent:fixup_post_load(old_save_data)
   if old_save_data.version < VERSIONS.BFS_PLANTING then
      -- Declare all the sv variables
      self._sv._soil_layer = old_save_data.soil_layer
      self._sv._plantable_layer = self:_create_underfield_layer('stonehearth_ace:mountain_folk:grower:underfield_layer:plantable')

      self._sv._harvestable_layer = old_save_data.harvestable_layer

      self._sv._location = old_save_data.location
      self._needs_plantable_layer_placement = true

      self._sv.current_undercrop_alias = old_save_data.undercrop_queue[1].uri
      self._sv.current_undercrop_details = old_save_data.undercrop_queue[1]

      self._sv.has_set_undercrop = true -- remoted to client for the UI
   end

   if old_save_data.version < VERSIONS.SUBSTRATE_PLOT_RENDERING then
      self._needs_substrate_plot_upgrade = true
   end

   if old_save_data.version < VERSIONS.FIXUP_INCONSISTENT_UNDERFIELD_LAYERS then
      self._needs_layer_validation = true
   end

   if old_save_data.version < VERSIONS.ADD_UNDERFIELD_TO_UNDERCROPS then
      for x, row in pairs(self._sv.contents) do
         for z, substrate_plot in pairs(row) do
            local undercrop = substrate_plot.contents
            if undercrop then
               undercrop:get_component('stonehearth_ace:undercrop')
                        :set_underfield(self, x, z)
            end
            substrate_plot.removed_listener = nil
            substrate_plot.harvestable_listener = nil
            substrate_plot.listening_to_undercrop_events = nil
         end
      end
   end
end

function GrowerUnderfieldComponent:fixup_substrate_plots()
   local old_contents = self._sv.contents
   for x=1, self._sv.size.x do
      for y=1, self._sv.size.y do
         local substrate_plot = old_contents[x][y]
         if substrate_plot then
            local substrate_plot_component = substrate_plot:get_component('stonehearth_ace:substrate_plot')
            local undercrop = substrate_plot_component:get_contents()
            local new_substrate_plot = {
               is_furrow = substrate_plot_component:is_furrow(),
               x = x,
               y = y,
               contents = undercrop,
            }
            if undercrop then
               local undercrop_component = undercrop:get_component('stonehearth_ace:undercrop')
               undercrop_component:set_underfield(self, x, y)
            end
            self._sv.contents[x][y] = new_substrate_plot
         end
      end
   end
end

function GrowerUnderfieldComponent:_validate_layers()
   -- make sure all the harvest and planting layer stuff are consistent
   local contents = self._sv.contents
   local plantable_layer_region = self._sv._plantable_layer:get_component('destination')
                                :get_region()

   local harvestable_layer_region = self._sv._harvestable_layer:get_component('destination')
                                       :get_region()

   local soil_layer_region = self._sv._soil_layer:get_component('destination')
                                :get_region()

   for x=1, self._sv.size.x do
      for y=1, self._sv.size.y do
         local substrate_plot = contents[x][y]
         if substrate_plot then
            local p = Point3(x - 1, 0, y - 1)
            soil_layer_region:modify(function(cursor)
               cursor:subtract_point(p)
            end)

            if substrate_plot.contents then
               plantable_layer_region:modify(function(cursor)
                  cursor:subtract_point(p)
               end)
               local undercrop = substrate_plot.contents:get_component('stonehearth_ace:undercrop')
            else
               harvestable_layer_region:modify(function(cursor)
                  cursor:subtract_point(p)
               end)
            end
         end
      end
   end
end

-- useful for making sure the harvest invariants are met.  expensive, though, so only
-- enable if you're debugging.
function GrowerUnderfieldComponent:_check_harvest_invariants()
   local harvestable_dst = self._sv._harvestable_layer:get_component('destination')

   local harvest_rgn = harvestable_dst:get_region():get()
   local harvest_reserved = harvestable_dst:get_reserved():get()
   for x, row in ipairs(self._sv.contents) do
      for y, substrate_plot in ipairs(row) do
         local undercrop = substrate_plot.contents
         local location = Point3(x - 1, 0, y - 1)

         radiant.log.write('', 1, 'checking on %d,%d - %s - %s (%d - %d = %d)', x, y, tostring(undercrop), location,
            harvest_rgn:get_area(), harvest_reserved:get_area(), harvest_rgn:get_area() - harvest_reserved:get_area())

         if undercrop then
            local undercrop_comp = undercrop:get_component('stonehearth_ace:undercrop')
            assert(undercrop_comp._sv._underfield, 'undercrop underfield has no underfield pointer!')

            if undercrop_comp:is_harvestable() then
               local undercrop_component = undercrop:get_component('stonehearth_ace:undercrop')
               local cx, cy = undercrop_component:get_underfield_offset()
               assert(x == cx and y == cy, 'undercrop underfield offset disagrees with actual location')
               assert(harvest_rgn:contains(location), 'harvestable undercrop not in harvest region')
            else
               assert(not harvest_rgn:contains(location), 'non harvestable undercropling in harvest region')
            end
         else
            assert(not harvest_rgn:contains(location), 'non undercrop in harvest region')
         end
      end
   end
end

function GrowerUnderfieldComponent:add_worker(worker)
   self._workers[worker:get_id()] = true
   self:_reconsider_underfields()
end

function GrowerUnderfieldComponent:remove_worker(worker)
   self._workers[worker:get_id()] = nil
   self:_reconsider_underfields()
end

function GrowerUnderfieldComponent:_reconsider_underfields()
   for _, layer in ipairs({self._sv._soil_layer, self._sv._plantable_layer, self._sv._harvestable_layer}) do
      stonehearth.ai:reconsider_entity(layer, 'worker count changed')
   end
end

function GrowerUnderfieldComponent:get_worker_count(this_worker)
   local result = 0
   for worker in pairs(self._workers) do
      if worker ~= this_worker:get_id() then
         result = result + 1
      end
   end
   return result
end

return GrowerUnderfieldComponent
