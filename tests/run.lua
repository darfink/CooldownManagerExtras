-- Offline test runner for Cooldown Manager Extras.
--
--   cd <addon root> && luajit tests/run.lua [-v] [name filter]
--
-- Loads the addon through CooldownManagerExtras.toc into a mock WoW client (tests/mock) and runs
-- every tests/cases/*.lua. Exit status is non-zero when any test fails.

local script = arg and arg[0] or "tests/run.lua"
local testsDir = script:match("^(.*)/[^/]*$") or "."
local root = testsDir .. "/.."

package.path = testsDir .. "/?.lua;" .. package.path

local verbose, filter = false, nil
for _, a in ipairs(arg or {}) do
	if a == "-v" then verbose = true else filter = a end
end

local Harness = require("harness")

-- Test files, alphabetical. Listed with `ls` because Lua 5.1 has no directory API.
local listing = io.popen('ls "' .. testsDir .. '/cases" 2>/dev/null')
local files = {}
for name in listing:lines() do
	if name:match("%.lua$") then files[#files + 1] = name end
end
listing:close()
table.sort(files)
assert(#files > 0, "no test files found in " .. testsDir .. "/cases")

for _, name in ipairs(files) do
	local chunk, err = loadfile(testsDir .. "/cases/" .. name)
	if not chunk then
		io.write("cannot load tests/cases/" .. name .. ": " .. tostring(err) .. "\n")
		os.exit(2)
	end
	chunk(Harness.T, Harness)
end

local ok = Harness.run(root, filter, verbose)
os.exit(ok and 0 or 1)
