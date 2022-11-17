local validator = radiant.validator

local SavedVariablesCallHandler = class()

function SavedVariablesCallHandler:storage_mark_changed(session, response, storage)
   validator.expect_argument_types({'Entity'}, storage)

   local storage_component = storage:get_component('stonehearth:storage')
   if storage_component then
      storage_component:mark_changed()
      return true
   else
      return false
   end
end

return SavedVariablesCallHandler
