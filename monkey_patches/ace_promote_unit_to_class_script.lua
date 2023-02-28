local AcePromoteUnitToClassScript = class()

function AcePromoteUnitToClassScript:start(ctx, data)
	local citizen = ctx:get(data.unit_reference)
	if citizen and data.job then
		local job_comp = citizen:get_component('stonehearth:job')
		--ace: before blindly promoting, look for restriction, and remove it by setting job=true
		local allowed = job_comp:get_allowed_jobs()
		if allowed then
			allowed[data.job] = true
			job_comp:set_allowed_jobs(allowed)
		end
		job_comp:promote_to(data.job)
	end
end

return AcePromoteUnitToClassScript