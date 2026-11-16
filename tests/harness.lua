-- Test harness: boots the addon in the mock client, runs tests, reports.

local Mock = require("mock.wow")
local Blizzard = require("mock.blizzard")

local Harness = {}
local ADDON_NAME = "CooldownManagerExtras"

local function readFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

local function dirname(path)
	return path:match("^(.*)/[^/]*$") or "."
end

---------------------------------------------------------------------------
-- Loading the addon through its .toc (read at run time)
---------------------------------------------------------------------------

function Harness.tocFiles(root)
	local toc = readFile(root .. "/" .. ADDON_NAME .. ".toc")
	assert(toc, "cannot read " .. root .. "/" .. ADDON_NAME .. ".toc")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" and not line:find("^#") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
end

local function loadLuaFile(H, ns, path)
	local chunk, err = loadfile(path)
	if not chunk then
		H.recordError("load error: " .. tostring(err), path)
		return
	end
	local ok, runErr = xpcall(chunk, function(e) return debug.traceback(tostring(e), 2) end, ADDON_NAME, ns)
	if not ok then
		H.recordError("error while loading " .. path .. ":\n" .. tostring(runErr))
	end
end

local function loadXmlFile(H, ns, path)
	local xml = readFile(path)
	if not xml then
		H.recordError("cannot read xml " .. path)
		return
	end
	local base = dirname(path)
	for tag, file in xml:gmatch("<(%a+)%s+file%s*=%s*['\"]([^'\"]+)['\"]") do
		file = file:gsub("\\", "/")
		if tag == "Script" then
			loadLuaFile(H, ns, base .. "/" .. file)
		elseif tag == "Include" then
			loadXmlFile(H, ns, base .. "/" .. file)
		end
	end
end

local function loadFiles(H, ns, root)
	for _, file in ipairs(Harness.tocFiles(root)) do
		local path = root .. "/" .. file
		if file:lower():match("%.xml$") then
			loadXmlFile(H, ns, path)
		else
			loadLuaFile(H, ns, path)
		end
	end
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------

-- opts:
--   viewers   list of viewer keys to create (default all four); PRD = false to skip it
--   setup     function(H) run after Blizzard frames exist, before the addon loads
--   saved     table assigned to CooldownManagerExtrasDB before ADDON_LOADED
--   login     false = stop after loading files (no events)
--   entering  false = skip PLAYER_ENTERING_WORLD
--   combat    true = InCombatLockdown() is true from the start
function Harness.boot(root, opts)
	opts = opts or {}
	local H = Mock.new()
	Blizzard.install(H)
	H.install()
	H.root = root

	local keys = opts.viewers or { "Essential", "Utility", "BuffIcon", "BuffBar" }
	for _, key in ipairs(keys) do
		H.makeViewer(key)
	end
	if opts.prd ~= false then
		H.makePRD()
	end
	if opts.combat then H.inCombat = true end
	if opts.setup then opts.setup(H) end
	if opts.saved then
		rawset(_G, "CooldownManagerExtrasDB", opts.saved)
	end

	local ns = {}
	H.ns = ns
	loadFiles(H, ns, root)
	H.CMP = ns.CMP

	-- LibEditMode's panel under Blizzard's Edit Mode dialog
	function H.extension()
		return ns.LibEditMode and ns.LibEditMode.internal and ns.LibEditMode.internal.extension
	end
	-- Widgets currently built in the panel, in order.
	function H.widgets()
		local ext = H.extension()
		return ext and ext.Settings.widgets or {}
	end
	-- Widget whose setting name equals `name` (INDENT prefixes are ignored: pass the visible name).
	function H.widget(name)
		for _, widget in ipairs(H.widgets()) do
			local n = widget.setting and widget.setting.name
			if n and (n == name or n:sub(-#name) == name) then return widget end
		end
	end
	-- Click an Expander header (its OnMouseUp script), then let queued timers run.
	function H.clickExpander(name)
		local widget = assert(H.widget(name), "no widget named " .. name)
		widget:GetScript("OnMouseUp")(widget)
		H.flush()
		return widget
	end
	-- Run the panel's mouse wheel script.
	function H.wheel(delta)
		local ext = H.extension()
		ext:GetScript("OnMouseWheel")(ext, delta)
	end

	if opts.login ~= false then
		H.fireEvent("ADDON_LOADED", ADDON_NAME)
		H.fireEvent("PLAYER_LOGIN")
		if opts.entering ~= false then
			H.fireEvent("PLAYER_ENTERING_WORLD", true, false)
		end
		H.flush()
		-- Core schedules one more update a second after becoming ready
		H.advance(1)
		H.flush()
	end
	return H
end

---------------------------------------------------------------------------
-- Assertions
---------------------------------------------------------------------------

local function show(v)
	local ok, s = pcall(function()
		if type(v) == "string" then return ("%q"):format(v) end
		return tostring(v)
	end)
	return ok and s or "<secret/unprintable>"
end

local T = {}
Harness.T = T

function T.eq(actual, expected, msg)
	if actual ~= expected then
		error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
	end
end
function T.ne(actual, unexpected, msg)
	if actual == unexpected then
		error(("%sdid not expect %s"):format(msg and (msg .. ": ") or "", show(actual)), 2)
	end
end
function T.truthy(v, msg)
	if not v then error((msg or "expected a truthy value") .. (", got " .. show(v)), 2) end
end
function T.falsy(v, msg)
	if v then error((msg or "expected a falsy value") .. (", got " .. show(v)), 2) end
end
function T.near(actual, expected, eps, msg)
	if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-6) then
		error(("%sexpected ~%s, got %s"):format(msg and (msg .. ": ") or "", show(expected), show(actual)), 2)
	end
end
function T.contains(haystack, needle, msg)
	if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
		error(("%sexpected %s to contain %s"):format(msg and (msg .. ": ") or "", show(haystack), show(needle)), 2)
	end
end
function T.errors(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then error((msg or "expected an error") .. ", but the call succeeded", 2) end
	if pattern and not tostring(err):find(pattern) then
		error(("expected error matching %q, got %s"):format(pattern, tostring(err)), 2)
	end
end
function T.noErrors(H, msg)
	if #H.errors > 0 then
		error((msg or "Lua errors were raised") .. ":\n  " .. table.concat(H.errors, "\n  "):sub(1, 3000), 2)
	end
end

-- True when any line of H.output contains `needle` (plain).
function Harness.printed(H, needle)
	for _, line in ipairs(H.output) do
		if line:find(needle, 1, true) then return true, line end
	end
	return false
end
T.printed = Harness.printed

---------------------------------------------------------------------------
-- Registry and runner
---------------------------------------------------------------------------

local tests = {}

-- T.test(name, [opts], fn(H)). opts = boot options plus:
--   knownBug = "file:line description"   the test documents an addon bug (see README)
--   allowErrors = true                   do not fail on recorded Lua errors
function T.test(name, opts, fn)
	if type(opts) == "function" then
		fn, opts = opts, {}
	end
	tests[#tests + 1] = { name = name, opts = opts or {}, fn = fn }
end

function Harness.run(root, filter, verbose)
	local pass, fail, known, unexpected = 0, 0, 0, 0
	local failures = {}
	local total = 0
	for _, test in ipairs(tests) do
		if not filter or test.name:lower():find(filter:lower(), 1, true) then
			total = total + 1
			local H
			local ok, err = xpcall(function()
				H = Harness.boot(root, test.opts)
				if not test.opts.allowBootErrors and not test.opts.allowErrors and #H.errors > 0 then
					error("errors while booting the addon:\n  " .. table.concat(H.errors, "\n  "):sub(1, 3000), 0)
				end
				test.fn(H, T)
				if not test.opts.allowErrors then
					T.noErrors(H, "Lua errors were recorded during the test")
				end
			end, function(e)
				return debug.traceback(tostring(e), 2)
			end)
			if H then
				H.uninstall()
			else
				-- boot itself blew up before H existed
				pcall(function() setmetatable(_G, nil) end)
			end
			local status
			if test.opts.knownBug then
				if ok then
					status = "UNEXPECTED PASS"
					unexpected = unexpected + 1
					failures[#failures + 1] = { name = test.name, err = "marked knownBug but passes now: " .. test.opts.knownBug }
				else
					status = "KNOWN BUG"
					known = known + 1
				end
			elseif ok then
				status = "PASS"
				pass = pass + 1
			else
				status = "FAIL"
				fail = fail + 1
				failures[#failures + 1] = { name = test.name, err = err }
			end
			io.write(("%-16s %s\n"):format(status, test.name))
			if status == "FAIL" or (status == "KNOWN BUG" and verbose) then
				local first = tostring(err):match("^[^\n]*") or ""
				io.write("    " .. first .. "\n")
				if status == "FAIL" then
					local rest = tostring(err):gsub("^[^\n]*\n?", "")
					for line in rest:gmatch("[^\n]+") do
						local noise = line:find("^%s*tests/harness.lua:") or line:find("^%s*tests/mock/[%w/]*.lua:")
							or line:find("^%s*%[C%]: in function 'xpcall'") or line:find("^%s*tests/run.lua:")
						if not noise then
							io.write("      " .. line .. "\n")
						end
					end
				end
			end
		end
	end
	io.write("\n")
	io.write(("%d tests: %d passed, %d failed, %d known addon bugs, %d unexpected passes\n"):format(total, pass, fail, known, unexpected))
	local bugs = {}
	for _, test in ipairs(tests) do
		if test.opts.knownBug and (not filter or test.name:lower():find(filter:lower(), 1, true)) then
			bugs[#bugs + 1] = test
		end
	end
	if #bugs > 0 then
		io.write("\nKnown addon bugs (tests marked knownBug):\n")
		for _, test in ipairs(bugs) do
			io.write(("  - %s\n      %s\n"):format(test.name, test.opts.knownBug))
		end
	end
	return fail + unexpected == 0, total
end

return Harness
