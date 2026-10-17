local Id = require("project.AssetId")
local LuaScript = {}
local classNames = setmetatable({}, {__mode = "k"})
-- 클래스 테이블에 Editor 필드를 추가하지 않고 현재 모듈 이름을 별도로 보관한다.
function LuaScript.name(class) return classNames[class] end

-- 에셋의 소속과 무관하게 같은 클래스 계약을 적용하고 require 동일성을 유지한다.
function LuaScript.scriptClass(definition, name, parent)
    local Script = require("core.Script")
    assert(type(definition) == "table", "Lua Class must return a table")
    assert(definition ~= Script, "Lua Class must return a definition or a derived Script class")
    assert(not definition.build and not definition.beginPlay, "Use load and editor-authored script attachments; build/beginPlay callbacks are no longer supported")
    if getmetatable(definition) then
        assert(Script.isClass(definition), "Lua Class must return a plain table or a Script:extend class")
    else definition = (parent or Script):extend(definition) end
    definition.scriptType = name
    classNames[definition] = name
    return definition
end

function LuaScript.validValue(kind, value)
    return require("core.PropertySchema").validValue(kind, value)
end

-- 일반 스크립트와 플러그인이 같은 에셋 경로 해석을 사용한다.
function LuaScript.moduleLoader(project, registry)
    -- 설치·활성 목록만 공유하고 실행 캐시는 각 세션이 소유한다.
    registry = registry:forProject(project)
    local modules, loadingModules = {}, {}
    local moduleRequire
    local function environment()
        return setmetatable({require = moduleRequire}, {__index = _G})
    end
    local function loadModule(reference, bytes)
        if modules[reference] ~= nil then return modules[reference] end
        assert(not loadingModules[reference], "Project module cycle: " .. reference)
        loadingModules[reference] = true
        local ok, value = pcall(function()
            bytes = bytes or assert(project:readSource(reference))
            local chunk = assert(loadstring(bytes, "@" .. reference))
            setfenv(chunk, environment())
            return chunk()
        end)
        loadingModules[reference] = nil
        assert(ok, value)
        modules[reference] = value == nil and true or value
        return modules[reference]
    end
    moduleRequire = function(name)
        if name == "Engine" then
            return setmetatable({}, {__index = function(_, key)
                if registry.scripts[key] then return assert(registry:loadScript(key)) end
                return require("Engine")[key]
            end})
        end
        local reference = type(name) == "string" and "Assets/" .. name:gsub("%.", "/") .. ".lua"
        if not reference or not project:getAssetId(reference) then return require(name) end
        return loadModule(reference)
    end
    registry.moduleRequire, registry.loadModule = moduleRequire, loadModule
    return moduleRequire, loadModule, registry
end

-- 검증용 프로젝트 뷰는 원본 레지스트리의 로딩 캐시를 공유하지 않는다.
function LuaScript.loader(project)
    if project then
        project.plugins = project.plugins or require("project.PluginRegistry").new(project,
            not project.rootPath and {manifests = {}, enabled = {}} or nil)
        if project.plugins.project ~= project then project.plugins = project.plugins:forProject(project) end
    end
    local loaded, visiting = {}, {}
    local loadModule, registry = require, nil
    if project then local moduleRequire; moduleRequire, loadModule, registry = LuaScript.moduleLoader(project, project.plugins) end
    local function load(reference, expectedKind, depth)
        if expectedKind == "script" and (reference == "Script" or registry and registry.scripts[reference]) then
            return registry:loadScript(reference)
        end
        local canonical, referenceError = project:getAssetReference(reference)
        if not canonical then return nil, referenceError end
        local pluginScript = registry.assetScripts and registry.assetScripts[canonical]
        if pluginScript then return registry:loadScript(pluginScript) end
        local key = project:getAssetId(canonical) or canonical
        if visiting[key] then return nil, "Lua Class inheritance cycle: " .. canonical end
        if (depth or 0) > 64 then return nil, "Lua Class inheritance is too deep" end
        local kind, kindError = project:getScriptKind(key)
        if not kind then return nil, kindError end
        if expectedKind and kind ~= expectedKind then return nil, "Expected a " .. expectedKind .. " Lua Class" end
        if loaded[key] then return loaded[key] end
        local path, pathError = project:resolveSourceFile(key)
        if not path then return nil, pathError end
        -- require로 가져온 클래스와 실제 부착 클래스가 같은 테이블을 사용한다.
        local ok, class = pcall(loadModule, canonical)
        if not ok then return nil, tostring(class) end
        if kind == "script" and require("core.Script").isClass(class) then
            local valid, script = pcall(LuaScript.scriptClass, class, canonical:match("([^/]+)%.lua$"))
            if not valid then return nil, tostring(script) end
            loaded[key] = script
            return script
        end
        if type(class) ~= "table" or getmetatable(class) then return nil, "Lua Class must return a plain table or a Script:extend class" end
        visiting[key] = true
        local function fail(err) visiting[key] = nil; return nil, err end
        local parent
        if class.extends ~= nil then
            if kind == "script" and (class.extends == "Script" or registry and registry.scripts[class.extends]) then
                local parentError
                parent, parentError = registry:loadScript(class.extends)
                if not parent then return fail(parentError) end
                -- 과거 공개 이름은 읽기 호환으로만 해석하고 로딩한 정의는 ID로 정규화한다.
                local source = registry.scripts[class.extends]
                class.extends = source and source.id or nil
            end
            if not parent and not Id.isValid(class.extends) then return fail("extends must be a script asset ID or built-in script") end
            local parentError
            if not parent then parent, parentError = load(class.extends, kind, (depth or 0) + 1) end
            if not parent then return fail(parentError) end
        end
        if kind == "script" then
            local valid, script = pcall(LuaScript.scriptClass, class, canonical:match("([^/]+)%.lua$"), parent)
            if not valid then return fail(tostring(script)) end
            loaded[key], visiting[key] = script, nil
            return script
        end
        local schema = {}
        for name, declaration in pairs(parent and parent.properties or {}) do schema[name] = declaration end
        if class.properties ~= nil and type(class.properties) ~= "table" then return fail("properties must be a table") end
        for name, declaration in pairs(class.properties or {}) do
            if type(name) ~= "string" or name == "" or type(declaration) ~= "table"
                or not LuaScript.validValue(declaration.type, declaration.default) then
                return fail("Invalid property declaration: " .. tostring(name))
            end
            if schema[name] and schema[name].type ~= declaration.type
                and not (require("core.PropertySchema").isTemplate(schema[name].type) and require("core.PropertySchema").isTemplate(declaration.type)) then return fail("Inherited property type cannot change: " .. name) end
            if declaration.group ~= nil and (type(declaration.group) ~= "string" or declaration.group == "") then return fail("Property group must be a non-empty string") end
            schema[name] = {type = declaration.type, default = declaration.default, group = declaration.group or schema[name] and schema[name].group}
        end
        for _, name in ipairs({"build", "load", "update"}) do
            if class[name] ~= nil and type(class[name]) ~= "function" then return fail(name .. " must be a function") end
        end
        class.properties, class.super = schema, parent
        classNames[class] = canonical:match("([^/]+)%.lua$") or canonical
        if parent then setmetatable(class, {__index = parent}) end
        loaded[key], visiting[key] = class, nil
        return class
    end
    if registry then registry.classLoader = load end
    return load
end

function LuaScript.load(project, reference, kind)
    return LuaScript.loader(project)(reference, kind)
end

function LuaScript.values(class, overrides)
    if overrides ~= nil and type(overrides) ~= "table" then return nil, "Property overrides must be an object" end
    local values = {}
    for name, declaration in pairs(class and class.properties or {}) do values[name] = declaration.default end
    for name, value in pairs(overrides or {}) do
        local declaration = class and class.properties[name]
        if not declaration or not LuaScript.validValue(declaration.type, value) then return nil, "Invalid property override: " .. tostring(name) end
        values[name] = value
    end
    return values
end

function LuaScript.compatibleOverrides(class, overrides)
    local result = {}
    for name, value in pairs(overrides or {}) do
        local declaration = class and class.properties[name]
        if declaration and LuaScript.validValue(declaration.type, value) and value ~= declaration.default then result[name] = value end
    end
    return result
end
return LuaScript
