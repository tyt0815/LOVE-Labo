local Assert = require("tests.Assert")
local tests = {}
local function add(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

add("Version CLI works without a project and preserves response schema version", function()
    local Cli, Json = require("editor.Cli"), require("project.Json")
    local request = Cli.parse({"--cli", "version"})
    local info = Cli.execute(request)
    Assert.equal(require("Version").getInfo().engineVersion, info.engineVersion)
    Assert.truthy(info.engineVersion:match("^%d+%.%d+%.%d+"))
    local bytes, ok = require("project.CliResponse").finish(true, info)
    Assert.equal(true, ok)
    local response = assert(Json.decode(bytes))
    Assert.equal(1, response.version)
    Assert.equal(info.engineVersion, response.result.engineVersion)
    local found = false
    for _, command in ipairs(Cli.execute({command = "help"}).commands) do
        if command == "version" then found = true end
    end
    Assert.equal(true, found)
    local Instructions = require("editor.ProjectInstructions")
    Assert.equal(info.displayVersion, Instructions.version)
    Assert.truthy(Instructions.files()[2].text:find(info.displayVersion, 1, true))
end)

add("Version formats packaged revision and dirty status without changing source version", function()
    local build, Version = require("BuildInfo"), require("Version")
    local revision, dirty = build.revision, build.dirty
    local ok, err = pcall(function()
        build.revision, build.dirty = "123456abcdef", true
        local info = Version.getInfo()
        Assert.equal(info.engineVersion .. "+123456abcdef.dirty", info.displayVersion)
        build.dirty = false
        Assert.equal(info.engineVersion .. "+123456abcdef", Version.getInfo().displayVersion)
    end)
    build.revision, build.dirty = revision, dirty
    assert(ok, err)
end)

return tests
