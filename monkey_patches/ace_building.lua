local Plan = require 'stonehearth.components.building2.plan.plan'
local Fixture = require 'stonehearth.components.building2.fixture'
local FixtureData = require 'lib.building.fixture_data'
local BlueprintsToBuildingPiecesJob = require 'stonehearth.components.building2.plan.jobs.blueprints_to_building_pieces_job'
local BuildingCompletionJob = require 'stonehearth.components.building2.building_completion_job'

local build_util = require 'stonehearth.lib.build_util'
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local rng = _radiant.math.get_default_rng()
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Cube3   = _radiant.csg.Cube3
local Color4   = _radiant.csg.Color4

local NewStructureOp = require 'components.building2.new_structure_op'
local MutateOp = require 'components.building2.mutate_op'
local DeleteStructureOp = require 'components.building2.delete_structure_op'
local StartOp = radiant.class()
function StartOp:__init()
   self._name = 'start'
end


local VERSIONS = {
   KILL_LEVELS = 1,
}


local log = radiant.log.create_logger('build.building')

local Building = require 'stonehearth.components.building2.building'
local AceBuilding = class()

AceBuilding._ace_old_activate = Building.activate
function AceBuilding:activate(loading)
   if not self._sv._banked_resources then
      self._sv._banked_resources = {}
   end

   if not self._sv._resource_delivery_entity then
      self:_create_resource_delivery_entity()
   end

   self._registered_materials_to_be_banked = {}
   self._registered_materials_by_entity = {}

   if self._sv._sunk == true then
      self._sv._sunk = 1
   end

   self:_ace_old_activate(loading)

   if self._sv.plan_job_status == stonehearth.constants.building.plan_job_status.COMPLETE then
      self:_create_resource_collection_tasks()
   end
end

AceBuilding._ace_old_destroy = Building.__user_destroy
function AceBuilding:destroy()
   self:_destroy_resource_delivery_entity()

   -- ACE: destroy structures this way to try to auto-fill water
   for id, s in pairs(self._sv._structures) do
      self:destroy_structure(s)
   end
   self._sv._structures = {}

   self:_ace_old_destroy()
end

function AceBuilding:_destroy_resource_delivery_entity()
   if self._sv._resource_delivery_entity then
      radiant.entities.destroy_entity(self._sv._resource_delivery_entity)
      self._sv._resource_delivery_entity = nil
   end
end

function AceBuilding:restore_terrain_region()
   assert(radiant.is_server)
   stonehearth.mining:restore_terrain(self._sv._terrain_region_w)
end

function AceBuilding:build(ignored_entities, insert_craft_requests)
   if self._sv._plan or self._sv._building_job then
      return self._sv.plan_job_status
   end

   -- If ignored_entities are specified, then we take this to mean we don't
   -- care about validation (because this is a terrain restoration).
   -- The building plan will still alert us to impossible-to-build structures,
   -- this just bypasses the 'you have intersecting stuff' test because the
   -- player didn't even design this.
   if radiant.empty(ignored_entities) and self:_any_invalid_blueprints() then
      self._sv.plan_job_status = stonehearth.constants.building.plan_job_status.INVALID_BLUEPRINTS
      return self._sv.plan_job_status
   end

   self._sv.plan_job_status = stonehearth.constants.building.plan_job_status.WORKING

   log:debug('%s starting planning job...', self._entity)
   self._sv.building_status = stonehearth.constants.building.building_status.PLANNING
   self.__saved_variables:mark_changed()

   local blueprints = {}
   for bid, bp in self._sv.blueprints:each() do
      blueprints[bid] = bp
   end

   local terrain_cutout = self:_calculate_terrain_cutout()
   self:_set_terrain_region_w(terrain_cutout)

   self._sv._building_job = radiant.create_controller('stonehearth:persistent_job_sequence', 'building plan', {
         blueprints = blueprints,
         ignored_entities = ignored_entities,
         building_entity = self._entity,
         insert_craft_requests = insert_craft_requests,
         terrain_cutout = terrain_cutout,
      })

   self:_attach_plan_job_listeners()

   self._sv._building_job
         :add_job('stonehearth:build2:jobs:blueprint')
         :add_job('stonehearth:build2:jobs:blueprints_to_building_pieces')
         :add_job('stonehearth:build2:jobs:building_piece_dependencies')
         :add_job('stonehearth:build2:jobs:plan')
         :start()

   return self._sv.plan_job_status
end

-- ACE: make sure water gets properly filled in where this structure used to be
function AceBuilding:destroy_structure(structure)
   log:debug('destroying structure %s', structure)
   local structure_comp = structure:get('stonehearth:build2:structure')
   -- could subtract out the terrain region here:  - self._sv._terrain_region_w
   stonehearth.hydrology:auto_fill_water_region(structure_comp:get_desired_shape_region():translated(structure_comp:get_origin()), function()
         local bid = structure_comp:get_bid()
         assert(self._sv._structures[bid])
      
         self._sv._structures[bid] = nil
         radiant.entities.destroy_entity(structure)
         self.__saved_variables:mark_changed()
         return true
      end)
end

-- ACE: instead of returning true if it's sunk, return the value of how much it's sunk
-- this is a 
function AceBuilding:is_sunk()
   if self._sv._sunk then
      return self._sv._sunk
   end

   local region = self:_calculate_terrain_cutout()

   if region:get_area() == 0 then
      return false
   end

   if not radiant.terrain.region_intersects_terrain(region, 0) then
      return false
   end

   local terrain_region = radiant.terrain.intersect_region(region)
   return self:_calculate_sunk_depth(terrain_region)
end

function AceBuilding:_calculate_sunk_depth(terrain_region)
   -- split the terrain region into contiguous regions
   -- and determine the deepest depth from surface level
   if terrain_region:empty() then
      return false
   else
      local split_regions = csg_lib.get_contiguous_regions(terrain_region)
      local max_depth = 0
      for _, region in ipairs(split_regions) do
         local bounds = region:get_bounds()
         log:debug('terrain region split into bounds %s', bounds)
         -- check each terrain slice to see if it's at ground level
         local slice_template = bounds:get_face(Point3.unit_y)
         for y = bounds.max.y - 1, bounds.min.y, -1 do
            local slice = region:intersect_cube(slice_template):translated(Point3.unit_y) - region
            if not slice:empty() then
               local terrain_clip = radiant.terrain.clip_region(slice)
               if not terrain_clip:empty() then
                  max_depth = math.max(max_depth, y - bounds.min.y + 1)
                  break
               end
            end

            slice_template:translate(-Point3.unit_y)
         end
      end
      return max_depth > 0 and max_depth or false
   end
end

function AceBuilding:_calculate_terrain_cutout()
   local regions = {}

   for _, bp in self._sv.blueprints:each() do
      local bp_c = bp:get('stonehearth:build2:blueprint')
      table.insert(regions, bp_c:get_data():get_world_shape())
   end
   
   self._sv._terrain_cutout = build_util.calculate_building_terrain_cutout(regions)
   return self._sv._terrain_cutout
end

function AceBuilding:get_terrain_cutout()
   return self._sv._terrain_cutout
end

function AceBuilding:_calculate_building_region()
   local region = Region3()
   for _, bp in self._sv.blueprints:each() do
      local bp_c = bp:get('stonehearth:build2:blueprint')
      region:add_region(bp_c:get_data():get_world_shape())
   end

   log:debug('building region calculated with bounds %s', region:get_bounds())
   return region
end

function AceBuilding:get_world_terrain_region()
   return self._sv._terrain_region_w
end

function AceBuilding:get_contiguous_terrain_regions()
   return self._sv._contiguous_terrain_regions
end

function AceBuilding:get_total_building_region()
   return self._sv._total_building_region
end

function AceBuilding:_set_terrain_region_w(region)
   local ore_kinds = radiant.terrain.get_config().selectable_kinds

   -- get the current terrain-tagged data for this region
   local tagged = radiant.terrain.intersect_region(region)
   local retagged = Region3()
   for cube in tagged:each_cube() do
      local kind = radiant.terrain.get_block_kind_from_tag(cube.tag)
      if ore_kinds[kind] then
         local height = cube.min.y
         local new_terrain_tag = stonehearth.world_generation:get_rock_terrain_tag_at_height(height)
         if new_terrain_tag then
            log:debug('replacing cached terrain kind %s (tag %s) with tag %s', kind, cube.tag, new_terrain_tag)
            cube.tag = new_terrain_tag
         end
      end
      retagged:add_cube(cube)
   end
   retagged:optimize('building terrain region')

   log:debug('terrain region calculated with bounds %s', retagged:get_bounds())

   self._sv._terrain_region_w = retagged
   self._sv._total_building_region = self:_calculate_building_region()
   self._sv._contiguous_terrain_regions = csg_lib.get_contiguous_regions(retagged)
   self._sv._sunk = self:_calculate_sunk_depth(retagged)
end

function AceBuilding:_on_plan_job_failed(payload)
   self:_destory_plan_job_listeners()

   for _, piece in ipairs(payload) do
      stonehearth.debug_shapes:show_box(piece, Color4(255, 0, 0, 255), 30000, {
            material = 'materials/always_on_top.material.json'
         })
   end
   self._sv._building_job:destroy()
   self._sv._building_job = nil
   self._sv.building_status = stonehearth.constants.building.building_status.NONE
   self._sv.plan_job_status = stonehearth.constants.building.plan_job_status.PLANNING_ERROR_GENERIC
   self._sv._sunk = nil

   --TODO: for now, just clean out our structures, since a new plan will regenerate them.
   --Eventually, we can just use a diffing mechanism to avoid this.
   for _, s in pairs(self._sv._structures) do
      radiant.entities.destroy_entity(s)
   end
   self._sv._structures = {}

   for _, f in pairs(self._sv._fixtures) do
      radiant.entities.destroy_entity(f)
   end
   self._sv._fixtures = {}

   self.__saved_variables:mark_changed()
end

AceBuilding._ace_old_pause_building = Building.pause_building
function AceBuilding:pause_building()
   local building_status = self:_ace_old_pause_building()
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:building_paused')
   return building_status
end

AceBuilding._ace_old_resume_building = Building.resume_building
function AceBuilding:resume_building()
   local building_status = self:_ace_old_resume_building()
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:building_resumed')
   return building_status
end

function AceBuilding:currently_building()
   return self:in_progress() and self._sv.building_status ~= stonehearth.constants.building.building_status.PAUSED
end

function AceBuilding:get_envelope_entity()
   return self._sv._envelope_entity
end

function AceBuilding:get_resource_delivery_entity()
   return self._sv._resource_delivery_entity
end

function AceBuilding:destroy_banked_resources()
   self._sv._banked_resources = {}
end

function AceBuilding:get_banked_resources()
   return self._sv._banked_resources
end

function AceBuilding:get_banked_resource_count(material)
   local registered_count = 0
   local registered = self._registered_materials_to_be_banked[material]
   if registered then
      for id, reg_amt in pairs(registered) do
         registered_count = registered_count + reg_amt
      end
   end

   local banked = self._sv._banked_resources[material]

   return (banked and banked.count or 0), registered_count
end

function AceBuilding:has_banked_resource(material)
   local banked = self._sv._banked_resources[material]
   return banked and banked.count > 0
end

function AceBuilding:get_remaining_resource_cost(entity)
   local remaining = self._sv.resource_cost
   if not next(remaining) then
      return remaining
   end
   
   -- if an entity is specified, ignore any materials registered to be banked by them
   local entity_id = entity and entity:get_id()
   local resources = {}
   for material, cost in pairs(remaining) do
      local amount = cost
      local registered = self._registered_materials_to_be_banked and self._registered_materials_to_be_banked[material]
      if registered then
         for id, reg_amt in pairs(registered) do
            if id ~= entity_id then
               amount = amount - reg_amt
            end
         end
      end

      if amount > 0 then
         resources[material] = amount
      end
   end

   return resources
end

function AceBuilding:register_material_to_be_banked(entity, material, item)
   local entity_id = entity:get_id()
   local registered_material = self._registered_materials_to_be_banked[material]
   if not registered_material then
      registered_material = {}
      self._registered_materials_to_be_banked[material] = registered_material
   end

   if not registered_material[entity_id] then
      local stacks_comp = item:get_component('stonehearth:stacks')
      local stacks = stacks_comp and stacks_comp:get_stacks() or 1
      registered_material[entity_id] = stacks
      self._registered_materials_by_entity[entity_id] = material
      
      radiant.events.trigger_async(self._entity, 'stonehearth:build2:costs_changed')

      return true
   end
end

function AceBuilding:unregister_material_to_be_banked(entity_id, material)
   material = material or self._registered_materials_by_entity[entity_id]
   local registered_material = self._registered_materials_to_be_banked[material]
   if registered_material then
      registered_material[entity_id] = nil
   end
   self._registered_materials_by_entity[entity_id] = nil
end

function AceBuilding:try_bank_resource(item, material)
   -- if the material is a number, it's actually an entity_id; get the corresponding material
   if radiant.util.is_number(material) then
      material = self._registered_materials_by_entity[material]
   end
   
   -- only bank it if this resource is still required
   local remaining = self._sv.resource_cost[material]
   if remaining then
      local banked = self._sv._banked_resources[material]
      if not banked then
         banked = {
            count = 0,
            quality = 0,
            quality_count = 0,
         }
         self._sv._banked_resources[material] = banked
      end

      local prev_count = banked.count

      local stacks_comp = item:get_component('stonehearth:stacks')
      local stacks = stacks_comp and stacks_comp:get_stacks() or 1
      banked.count = banked.count + stacks
      -- storing quality weighted by count; TODO: when the building is completed, total overall quality can then be evaluated
      banked.quality_count = banked.quality_count + stacks
      banked.quality = banked.quality + stacks * radiant.entities.get_item_quality(item)

      remaining = remaining - stacks
      if remaining <= 0 then
         self._sv.resource_cost[material] = nil
      else
         self._sv.resource_cost[material] = remaining
      end
      self.__saved_variables:mark_changed()

      -- technically possible for a slightly negative banked count to then have only 1-2 stacks of a resource banked
      -- and we only want to alert people if we didn't have any banked already
      if banked.count > 0 and prev_count <= 0 then
         radiant.events.trigger_async(self._entity, 'stonehearth_ace:material_resource_banked', material)
      end

      return true
   end
end

function AceBuilding:spend_banked_resource(material, amount)
   local banked = self._sv._banked_resources[material]
   if banked then
      -- no need for a 0 check, it can go negative since it's the overall total for completing the building
      -- but isn't fully supplied upfront
      banked.count = banked.count - amount
   end
end

function AceBuilding:get_building_quality()
   if self._sv.quality then
      return self._sv.quality
   end

   local quality, count = 0, 0
   for _, resource in pairs(self._sv._banked_resources) do
      quality = quality + resource.quality
      count = count + resource.quality_count
   end

   if count > 0 then
      quality = quality / count
   else
      quality = 1
   end
   log:debug('%s building quality changed to: %s', self._entity, quality)

   return quality
end

AceBuilding._ace_old__calculate_remaining_resource_cost = Building._calculate_remaining_resource_cost
function AceBuilding:_calculate_remaining_resource_cost()
   self:_ace_old__calculate_remaining_resource_cost()

   local remaining = self._sv.resource_cost
   for mat, resource in pairs(self._sv._banked_resources) do
      if remaining[mat] then
         remaining[mat] = remaining[mat] - resource.count
         if remaining[mat] < 1 then
            remaining[mat] = nil
         end
      end
   end
   self.__saved_variables:mark_changed()
end

function AceBuilding:_on_building_start(plan, envelope_w, root_point, terrain_region_w)
   for bid, s in pairs(self:get_all_structures()) do
      self._sv._remaining_resource_costs[bid] = s:get('stonehearth:build2:structure'):get_remaining_resources()
   end

   -- ACE: this gets set at the beginning now
   --self._sv._terrain_region_w = terrain_region_w

   self._sv.building_status = stonehearth.constants.building.building_status.BUILDING

   self._sv._envelope_entity = radiant.entities.create_entity('stonehearth:build2:entities:envelope')
   self._sv._envelope_entity:get('destination'):set_region(radiant.alloc_region3())
   self._sv._envelope_entity:get('destination'):get_region():modify(function(cursor)
         cursor:copy_region(envelope_w)
      end)
   radiant.terrain.place_entity_at_exact_location(self._sv._envelope_entity, Point3.zero)

   self._sv._root_point = root_point
   self._sv._plan = plan
   self._sv._plan:start()
   self._sv._building_job:destroy()
   self._sv._building_job = nil
   self._sv.plan_job_status = stonehearth.constants.building.plan_job_status.COMPLETE

   self._plan_complete_listener = radiant.events.listen_once(self._sv._plan, 'stonehearth:build2:plan:complete', self, self._on_plan_complete)

   radiant.events.trigger_async(self._entity, 'stonehearth:build2:plan:start')

   self.__saved_variables:mark_changed()

   -- ACE: set up resource collection
   self:_create_resource_delivery_entity()
   self:_create_resource_collection_tasks()
end

function AceBuilding:_create_resource_delivery_entity()
   local region = self._sv.support_region:get()
   if region:empty() then
      -- try using the top layer of the terrain cutout, inflated by 1
      if self._sv._terrain_cutout and not self._sv._terrain_cutout:empty() then
         region = self._sv._terrain_cutout:inflated(Point3(1, 0, 1)):inflated(Point3.unit_y)
      else
         -- try the building envelope
         local env_region = self._sv._envelope_entity and self._sv._envelope_entity:get_component('destination'):get_region():get()
         if env_region and not env_region:empty() then
            local bounds = region:get_bounds()
            region = csg_lib.get_region_footprint(region):extruded('y', 0, bounds.max.y - bounds.min.y - 1)
         end
      end
   end

   self._sv._resource_delivery_entity = radiant.entities.create_entity('stonehearth_ace:build2:entities:resource_delivery')
   local destination = self._sv._resource_delivery_entity:get('destination')
   destination:set_region(radiant.alloc_region3())
   destination:get_region():modify(function(cursor)
         cursor:copy_region(region)
      end)
   destination:set_auto_update_adjacent(true)
   radiant.terrain.place_entity_at_exact_location(self._sv._resource_delivery_entity, Point3.zero)
end

AceBuilding._ace_old__on_plan_complete = Building._on_plan_complete
function AceBuilding:_on_plan_complete()
   self:_destroy_resource_collection_tasks()
   -- we also no longer care about banked resources, but let's keep the overall quality value around
   self._sv.quality = self:get_building_quality()
   self._sv._banked_resources = {}

   self:_destroy_resource_delivery_entity()

   self:_ace_old__on_plan_complete()

   -- required to actually clear out the resource cost so it doesn't show the missing resources alert overlay
   self:_calculate_remaining_resource_cost()
end

function AceBuilding:_create_resource_collection_tasks()
   self:_calculate_remaining_resource_cost()
   stonehearth.town:get_town(self._sv.player_id):create_resource_collection_tasks(self._entity, self._sv.resource_cost)
end

function AceBuilding:_destroy_resource_collection_tasks()
   stonehearth.town:get_town(self._sv.player_id):destroy_resource_collection_tasks(self._entity)
end

function AceBuilding:instamine()
   if self._sv._plan then
      -- the plan relies on async events and only a single node being active at once
      -- so we can only complete the current node (if it's a mining node);
      -- this is okay because there should only ever be a single mining node,
      -- and it should be the first node in the plan
      local mining_node = self._sv._plan:get_active_node()
      if mining_node.__classname == 'stonehearth:NewMiningNode' then
         mining_node:instamine()
      end
   end
end

function AceBuilding:instabuild()
   self:_destroy_resource_delivery_entity()
   self:_destory_plan_job_listeners()

   if self._building_unveil_listener then
      self._building_unveil_listener:destroy()
      self._building_unveil_listener = nil
   end

   if self._sv._plan then
      self._sv._plan:destroy()
      self._sv._plan = nil
   end

   if self._sv._building_job then
      self._sv._building_job:destroy()
      self._sv._building_job = nil
   end

   if self._sv._envelope_entity then
      radiant.entities.destroy_entity(self._sv._envelope_entity)
   end
   self._sv._envelope_entity = nil

   self._sv._scaffolding_set:destroy()
   self._sv._scaffolding_set = radiant.create_controller('stonehearth:build2:scaffolding_set', self._entity)

   for _, req in pairs(self._sv._reachability_ladder_handles) do
      -- We're manually blowing up the ladders, so it's quite possible to have multiple
      -- reachability ladder requests that point to the same ladder here, so
      -- double check the builder even exists!
      if req:is_valid() then
         local l = req:get_builder() and req:get_builder():get_ladder() or nil
         if l and l:is_valid() then
            req:get_builder():destroy()
         end
      end
   end
   self._sv._reachability_ladder_handles = {}

   local terrain_cutout = self:_calculate_terrain_cutout()
   self:_set_terrain_region_w(terrain_cutout)
   radiant.terrain.subtract_region(terrain_cutout)

   if radiant.empty(self._sv._structures) then
      local added_structures = {}
      local removed_structures = {}
      local mutated_structures = {}
      local removed_voxels_ws = {}
      local added_fixtures = {}

      for _, bp in self._sv.blueprints:each() do
         bp:get('stonehearth:build2:blueprint'):diff(
            added_structures,
            removed_structures,
            mutated_structures,
            removed_voxels_ws,
            added_fixtures)
      end

      for _, s in pairs(added_structures) do
         local structure_entity = BlueprintsToBuildingPiecesJob.create_structure(s, self._entity)
         self:add_structure(structure_entity)
      end

      if radiant.empty(self._sv._fixtures) then
         for _, f in pairs(added_fixtures) do
            local fixture_entity = BlueprintsToBuildingPiecesJob.create_fixture(f, self._entity)
            self:add_fixture(fixture_entity)
         end
      end
   end

   for _, s in pairs(self._sv._structures) do
      s:get('stonehearth:build2:structure'):instabuild(Region3())
   end

   for _, f in pairs(self._sv._fixtures) do
      f:get('stonehearth:build2:fixture'):instabuild()
   end

   self._sv.building_status = stonehearth.constants.building.building_status.FINISHED
   radiant.events.trigger_async(self._entity, 'stonehearth:build2:plan:stop')
   self.__saved_variables:mark_changed()
end

return AceBuilding
