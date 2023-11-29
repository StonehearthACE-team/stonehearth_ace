local Point3 = _radiant.csg.Point3
local template_utils = require 'stonehearth.lib.building.template_utils'
local BuildingDestructionJob = require 'stonehearth.components.building2.building_destruction_job'
local Building = 'stonehearth:build2:building'

local BuildingService = require 'stonehearth.services.server.building.building_service'
local AceBuildingService = class()

function AceBuildingService:build(building_id, opt_ignored_entities, insert_craft_requests)
   return self:_get_building(building_id):get(Building):build(opt_ignored_entities or {}, insert_craft_requests)
end

function AceBuildingService:build_command(session, response, building_id, zero_point, insert_craft_requests)
   local job_status = self:build(building_id, nil, insert_craft_requests)
   response:resolve(job_status)
end

function AceBuildingService:blow_up_building(building_id, player_id, restore_terrain)
   assert(player_id, 'player_id required for this call')
   
   local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
   player_jobs_controller:remove_craft_orders_for_building(building_id)

   if self._sv._in_progress_destruction[building_id] then
      return self:_get_random_building({[building_id] = true}, player_id)
   end
   local b = self:get_building(building_id)

   if not b then
      return self:_get_random_building({[building_id] = true}, player_id)
   end

   if restore_terrain then
      b:get(Building):restore_terrain_region()
   end

   local job = BuildingDestructionJob(b)
   self._sv._in_progress_destruction[building_id] = job

   radiant.events.listen_once(job, 'stonehearth:build2:building_destruction:complete', self, self.destroy_building)

   job:start()

   local player_id = radiant.entities.get_player_id(b)
   b:get('stonehearth:build2:building'):mark_ready_for_destruction()

   local next_id = self:_get_random_building({[building_id] = true}, player_id)

   if not next_id then
      next_id = self:_create_new_building(player_id)
   end
   self.__saved_variables:mark_changed()

   return next_id
end

function AceBuildingService:load_building_from_data(player_id, template_id, offset, rot_point, rotation, template)
   local id = self:_create_new_building(player_id)
   offset = Point3(offset.x, offset.y, offset.z)
   rot_point = Point3(rot_point.x, rot_point.y, rot_point.z)
   rotation = tonumber(rotation)
   local ignore_fixture_quality = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'ignore_building_template_fixture_quality', true)
   return template_utils.load_template_from_data(self._sv.buildings:get(id), template_id, self:get_next_bid(), offset, rot_point, rotation, template, ignore_fixture_quality)
end

function AceBuildingService:load_building(player_id, template_id, offset, rot_point, rotation)
   local id = self:_create_new_building(player_id)
   offset = Point3(offset.x, offset.y, offset.z)
   rot_point = Point3(rot_point.x, rot_point.y, rot_point.z)
   rotation = tonumber(rotation)
   local ignore_fixture_quality = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'ignore_building_template_fixture_quality', true)
   return template_utils.load_template(self._sv.buildings:get(id), template_id, self:get_next_bid(), offset, rot_point, rotation, ignore_fixture_quality)
end

function AceBuildingService:destroy_building_command(session, response, building_id, restore_terrain)
   local b = self:get_building(building_id)
   if radiant.entities.get_player_id(b) == session.player_id then
      local new_id = nil
      if building_id then
         new_id = self:blow_up_building(building_id, session.player_id, restore_terrain)
      end

      response:resolve(new_id)
   else
      response:resolve(building_id)
   end
end

return AceBuildingService