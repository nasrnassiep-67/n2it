-- N2IT: wake an extension's iPhones (VoIP push) before FreeSWITCH looks up where to ring it.
-- Runs as an API call inside the extension dial string, before ${sofia_contact(...)}:
--   ${lua(n2it_push_wake.lua user=${dialed_user} domain=${dialed_domain} number=${caller_id_number} name=${url_encode(${caller_id_name})})}
-- Asks the push gateway (http://127.0.0.1/push/notify.php) to push. If a push went out, waits up to
-- WAIT_MS for one of the extension's registrations to be new or refreshed, so the woken phone is
-- included when the call rings. Writes nothing into the dial string; any failure just rings as normal.
-- Source: /root/voip/n2it-app/push/, installed to /usr/share/freeswitch/scripts/.

-- Everything runs under pcall: an error must never put text into the dial string.
local ok, err = pcall(function()
	local WAIT_MS, STEP_MS = 8000, 200

	local args = {}
	for _, a in ipairs(argv) do
		local k, v = a:match("^(%w+)=(.*)$")
		if k then args[k] = v end
	end
	local user, domain = args.user or "", (args.domain or ""):lower()

	if not user:match("^%d%d+$") or not domain:match("^[%w%-]+%.voip%.n2it%.co%.za$") then return end
	local number = (args.number or ""):gsub("[^%d%+%*#]", ""):sub(1, 32)
	local name = (args.name or ""):gsub("[^%w%%%.%-_~]", ""):sub(1, 180)    -- already URL-encoded

	local api = freeswitch.API()

	-- "Call-ID|EXP" for each registration of this exact user; a new phone or a re-REGISTER changes the set.
	local function registrations()
		local out = api:executeString("sofia status profile internal reg " .. user .. "@" .. domain) or ""
		local set, call_id, matched = {}, nil, false
		for line in out:gmatch("[^\n]+") do
			local cid = line:match("^Call%-ID:%s*(%S+)")
			if cid then call_id, matched = cid, false end
			local u = line:match("^User:%s*(%S+)")
			if u then matched = (u == user .. "@" .. domain) end
			local exp = line:match("^Status:.*EXP%(([^)]+)%)")
			if exp and matched and call_id then set[call_id .. "|" .. exp] = true end
		end
		return set
	end

	local before = registrations()
	local p = io.popen("curl -s -m 4 http://127.0.0.1/push/notify.php" ..
		" -d user=" .. user .. " -d domain=" .. domain .. " -d number=" .. number ..
		" --data-raw 'name=" .. name .. "'")
	local reply = p and p:read("*a") or ""
	if p then p:close() end
	local sent = tonumber(reply:match('"sent":(%d+)') or "0")
	if sent == 0 then return end

	local waited = 0
	while waited < WAIT_MS do
		freeswitch.msleep(STEP_MS)
		waited = waited + STEP_MS
		for k in pairs(registrations()) do
			if not before[k] then
				freeswitch.consoleLog("NOTICE", "[n2it_push] " .. user .. "@" .. domain .. " re-registered after " .. waited .. " ms\n")
				freeswitch.msleep(300)                     -- let the registration settle before the INVITE
				return
			end
		end
	end
	freeswitch.consoleLog("WARNING", "[n2it_push] " .. user .. "@" .. domain .. ": pushed " .. sent .. ", no re-register within " .. WAIT_MS .. " ms\n")
end)
if not ok then freeswitch.consoleLog("ERR", "[n2it_push] " .. tostring(err) .. "\n") end
stream:write("")
