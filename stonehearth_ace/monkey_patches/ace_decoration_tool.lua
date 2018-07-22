local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local Point3 = _radiant.csg.Point3
local FixtureData = require 'stonehearth.lib.building.fixture_data'

local build_util = require 'stonehearth.lib.build_util'
local mutation_utils = require 'stonehearth.lib.building.mutation_utils'
local fixture_utils = require 'stonehearth.lib.building.fixture_utils'

local log = radiant.log.create_logger('decoration_tool')

local AceDecorationTool = radiant.class()

function AceDecorationTool:_setup_entity(uri)
   self._masked_bids = {}
   self._fixture_uri = uri
   self.placement_test_entity = radiant.entities.create_entity(self._fixture_uri)
   self.entity_forms = entity_forms_lib.get_root_entity(self.placement_test_entity)
      :get('stonehearth:entity_forms')

   self.local_bounds = fixture_utils.bounds_from_entity(self.placement_test_entity)
   self.bounds_origin = fixture_utils.bounds_origin_from_entity(self.placement_test_entity)

   -- TODO: actually, do allow it!  But only in 180 increments.
   -- don't allow rotation if we're placing stuff on the wall
   self._rotation_disabled = self.entity_forms:is_placeable_on_wall() and not self.entity_forms:is_placeable_on_ground()
   self._rotation = 0
   self._allow_ground = self.entity_forms:is_placeable_on_ground()
   self._allow_walls = self.entity_forms:is_placeable_on_wall()
   local portal = self.placement_test_entity:get('stonehearth:portal')
   self._embedded = portal and not portal.horizontal
   self._in_floor = portal and portal.horizontal
   self._fence = self.entity_forms:is_fence()
   radiant.entities.destroy_entity(self.placement_test_entity)
end

function AceDecorationTool:_calculate_stab_point(p)
   return fixture_utils.find_fixture_placement(p, self._widget, self._embedded, self._fence, self.local_bounds, self.bounds_origin, self._allow_ground, self._rotation, self._allow_walls, self._in_floor)
end

function AceDecorationTool:_set_fixture_data(owner, location_w, normal, rotation)
   if not location_w then
      return
   end


   local owner_bid = -1
   local owner_sub_bid = nil
   if radiant.entities.get_entity_data(owner, 'stonehearth:build2:widget') then
      local c = owner:get(radiant.entities.get_entity_data(owner, 'stonehearth:build2:widget').component)
      owner_bid = c:get_data():get_bid()

      if c:get_data().get_wall_id then
         owner_sub_bid = c:get_data():get_wall_id()
      end
	  -- paulthegreat: only added this part
	  if c:get_data().get_floor_id then
         owner_sub_bid = c:get_data():get_floor_id()
      end
   end

   local origin = Point3.zero
   if owner_bid ~= -1 then
      local owner_data = stonehearth.building:get_data(owner_bid)
      origin = owner_data:get_origin()
   end
   if normal.y == 0 then
      rotation = build_util.normal_to_rotation(normal)
   end

   if owner_bid > 0 and stonehearth.building:get_data(owner_bid):get_building_id() ~= stonehearth.building:get_current_building_id() then
      return
   end

   self._data = FixtureData.Make(
      stonehearth.building:get_current_building_id(),
      self._bid,
      self._fixture_uri,
      self._quality,
      owner_bid,
      location_w - origin,
      normal,
      owner_sub_bid,
      rotation)

   if not self._blueprint then
      self._blueprint = radiant.entities.create_entity('stonehearth:build2:entities:fixture_blueprint', self._data)
      self._bp_c = self._blueprint:get('stonehearth:build2:blueprint')
      self._bp_c:init(self._data)
      stonehearth.building:add_blueprint(self._blueprint)

      self._widget = radiant.entities.create_entity(self._data:get_fixture_uri())
      self._widget:add_component('destination')
      self._widget:add_component('stonehearth:ui:widget')
      self._widget:add_component('stonehearth:build2:fixture_widget'):from_blueprint(self._bp_c)
   else
      self._bp_c:update_data(self._data)
   end

   stonehearth.building:begin_commit()
   mutation_utils.create(self._data)

   local modified, added, removed = stonehearth.building:get_all_mutation_data()

   stonehearth.building:end_commit()

   -- Take all the data, and commit it!
   for id, data in pairs(modified) do
      local widget = stonehearth.building:get_widget(id)
      -- It's actually possible for this code to race against widget creation,
      -- so even though the data is there, make sure we don't call preview on something
      -- that doesn't yet exist on the client in visual form!
      if widget then
         widget:preview_data(data)
      end
   end

   for id, data in pairs(added) do
      local widget = stonehearth.building:get_widget(id)
      if widget then
         widget:preview_data(data)
      end

      if id == self._data:get_bid() then
         self._data = data
      end
   end
end

return AceDecorationTool
