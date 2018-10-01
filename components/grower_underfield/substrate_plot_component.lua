local Point3 = _radiant.csg.Point3

local SubstratePlotComponent = class()

local VERSIONS = {
   ZERO = 0,
   MARK_VARIABLES_PRIVATE = 1,
   DELETED = 2
}

function SubstratePlotComponent:get_version()
   return VERSIONS.DELETED
end

function SubstratePlotComponent:initialize()
   self._sv._contents = nil
   self._sv._is_substrate = false
end

function SubstratePlotComponent:destroy()
   self._sv._contents = nil
end

function SubstratePlotComponent:is_substrate()
   return self._sv._is_substrate
end

function SubstratePlotComponent:get_contents()
   return self._sv._contents
end

function SubstratePlotComponent:fixup_post_load(old_save_data)
   if old_save_data.version < VERSIONS.MARK_VARIABLES_PRIVATE then
      -- Declare all the sv variables
      self._sv._fertility = old_save_data.fertility
      self._sv._moisture = old_save_data.moisture
      self._sv._fertility_category = old_save_data.fertility_category
      self._sv._parent_underfield = old_save_data.parent_underfield
      self._sv._underfield_location = old_save_data.underfield_location
      self._sv._contents = old_save_data.contents
      self._sv._is_substrate = old_save_data.is_substrate
   end
end
return SubstratePlotComponent
