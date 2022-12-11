local SwitchWeatherScript = class()

function SwitchWeatherScript:start(ctx, data)
   stonehearth.weather:_switch_to(data.weather_uri, ctx.player_id)
end

return SwitchWeatherScript
