local Assert = require("tests.assert")
local Theme = require("editor.theme")
local Json = require("editor.json")
local tests = {}
local function add(name, fn)
    tests[#tests + 1] = { name = name, fn = function()
        local ok, err = pcall(fn)
        Theme.load()
        if not ok then error(err, 0) end
    end }
end

local function reader(settings, themes)
    return function(path)
        if path == "editor/settings.json" then return settings end
        if themes and themes[path] ~= nil then return themes[path] end
    end
end

add("theme selection supports partial colors alpha and bundled Atom One Light", function()
    local text = assert(Json.encode({version = 1, colors = {text = "#12345680"}}))
    assert(Theme.load(reader('{"version":1,"theme":"custom"}', { ["editor/themes/custom.json"] = text })))
    Assert.equal("custom", Theme.name)
    Assert.equal(0x12 / 255, Theme.color("text")[1])
    Assert.equal(0x80 / 255, Theme.color("text")[4])
    Assert.equal(0x80 / 255 * 0.5, Theme.color("text", 0.5)[4])
    Assert.truthy(Theme.color("surface"))
    assert(Theme.load(function(path)
        if path == "editor/settings.json" then return '{"version":1,"theme":"atom-one-light"}' end
        return love.filesystem.read(path)
    end))
    Assert.equal("atom-one-light", Theme.name)
    Assert.truthy(Theme.color("background")[1] > Theme.color("text")[1])
end)

add("invalid missing and unsafe theme settings reset to default", function()
    for _, settings in ipairs({
        '{"version":1}', '{"version":1,"theme":"missing"}', '{"version":1,"theme":"../escape"}',
        '{"version":1,"theme":false}', '{"version":2,"theme":"custom"}', 'bad JSON'
    }) do
        assert(Theme.load(reader('{"version":1,"theme":"custom"}', {
            ["editor/themes/custom.json"] = '{"version":1,"colors":{"surface":"#FF0000"}}'
        })))
        Theme.load(reader(settings))
        Assert.equal("default", Theme.name)
        Assert.truthy(Theme.color("surface")[1] < 0.5)
    end
    assert(Theme.load(function() return nil end))
    Assert.equal("default", Theme.name)
    Assert.truthy(Theme.color("text"))
end)

add("invalid theme colors fail atomically and unreadable settings still render", function()
    for _, text in ipairs({
        '{"version":1,"colors":{"surface":"#FFFFFF","text":"no-color"}}',
        '{"version":1,"colors":{"surface":[1,2,3]}}',
        '{"version":1,"colors":{"typo":"#FFFFFF"}}',
        '{"version":2,"colors":{}}', 'invalid JSON'
    }) do
        local ok, err = Theme.load(reader('{"version":1,"theme":"custom"}', { ["editor/themes/custom.json"] = text }))
        Assert.equal(false, ok)
        Assert.truthy(err)
        Assert.equal("default", Theme.name)
        Assert.truthy(Theme.color("surface")[1] < 0.5)
    end
    assert(Theme.load(function()
        error("unreadable settings")
    end))
    Theme.setColor("surface")
    Theme.clear("background")
    Assert.truthy(Theme.color("text")[1] > Theme.color("surface")[1])
end)

add("built in default never depends on external theme files", function()
    for _, settings in ipairs({ '{"version":1}', '{"version":1,"theme":"default"}' }) do
        local paths = {}
        assert(Theme.load(function(path)
            paths[#paths + 1] = path
            if path == "editor/settings.json" then return settings end
            -- 외부 default.json이 있어도 내장 기본값을 덮어쓰면 안 된다.
            return '{"version":1,"colors":{"surface":"#FFFFFF"}}'
        end))
        Assert.equal(1, #paths)
        Assert.equal("editor/settings.json", paths[1])
        Assert.equal("default", Theme.name)
        Assert.truthy(Theme.color("surface")[1] < 0.5)
    end
end)

add("partial widget colors stay independent and inherit omitted defaults", function()
    assert(Theme.load(function() return nil end))
    local iconDefault = {unpack(Theme.color("iconBackground"))}
    assert(Theme.load(reader('{"version":1,"theme":"custom"}', {
        ["editor/themes/custom.json"] = '{"version":1,"colors":{"button":"#112233"}}'
    })))
    Assert.equal(0x11 / 255, Theme.color("button")[1])
    for i = 1, 4 do Assert.equal(iconDefault[i], Theme.color("iconBackground")[i]) end
    Assert.truthy(Theme.color("input"))
    Assert.truthy(Theme.color("grid"))
end)

return tests
