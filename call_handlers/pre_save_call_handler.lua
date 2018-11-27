--[[
   Instead of immediately calling 'radiant:client:save_game', save functions point here first so that any pre-save
   actions necessary can be performed. This is a way to use _sv for storing large amounts of data and only perform
   mark_changed() right before saving.
]]

local PreSaveCallHandler = class()

local _pre_save_calls = {}
local _queued_calls = {}

function PreSaveCallHandler:register_pre_save_call_command(session, response, call, args)
   if call then
      _pre_save_calls[call] = {args = args}
   end
end

function PreSaveCallHandler:perform_pre_save_calls_command(session, response)
   if #_queued_calls > 0 then
      response:reject({})
   else
      for call, details in pairs(_pre_save_calls) do
         table.insert(_queued_calls, {call = call, args = details.args})
      end

      self:_perform_next_queued_call(response)
   end
end

function PreSaveCallHandler:_perform_next_queued_call(response)
   local call = table.remove(_queued_calls)
   if not call then
      response:resolve({})
   else
      radiant.call(call.call, call.args)
      :done(function(result)
         self:_perform_next_queued_call(response)
      end)
   end
end

-- client call
function PreSaveCallHandler:save_game(session, response, save_id, args)
   _radiant.call('stonehearth_ace:perform_pre_save_calls_command')
   :done(function(result)
      _radiant.call('radiant:client:save_game', save_id, args)
   end)
end

return PreSaveCallHandler