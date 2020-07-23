--[[
   used in conjunction with the connection component, this component manages dynamic connector regions
   that aren't part of specific other components
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('dynamic_connection')

local DynamicConnectionComponent = class()

function DynamicConnectionComponent:initialize()
   self._sv._connector_regions = {}
   self._json = radiant.entities.get_json(self)
end

function DynamicConnectionComponent:create()
   self._is_create = true
end

-- use if you don't want to override an existing connector region
function DynamicConnectionComponent:add_region(type, id, initial_region)
   local regions = self:_get_type_regions(type)
   if regions[id] then
      return
   end

   self:update_region(type, id, initial_region)
end

-- updates or adds the connector region
function DynamicConnectionComponent:update_region(type, id, region)
   local regions = self:_get_type_regions(type)
   local conn_reg = regions[id]

   if not conn_reg then
      conn_reg = _radiant.sim.alloc_region3()
      regions[id] = conn_reg
   end

   conn_reg:modify(function(cursor)
      cursor:copy_region(region or Region3())
   end)
end

function DynamicConnectionComponent:get_region(type, id)
   local regions = self:_get_type_regions(type)
   local region = regions[id]
   if not region then
      self:add_region(type, id)
      region = regions[id]
   end

   return region
end

function DynamicConnectionComponent:_get_type_regions(type)
   local regions = self._sv._connector_regions[type]
   if not regions then
      regions = {}
      self._sv._connector_regions[type] = regions
   end

   return regions
end

return DynamicConnectionComponent
