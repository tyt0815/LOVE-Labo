local Id = require("project.AssetId")
local LuaScript = {}
local classNames = setmetatable({}, {__mode = "k"})
-- 클래스 테이블에 Editor 필드를 추가하지 않고 현재 모듈 이름을 별도로 보관한다.
function LuaScript.name(class) return classNames[class] end

function LuaScript.validValue(kind, value)
    return require("core.PropertySchema").validValue(kind, value)
end

-- 일반 스크립트와 플러그인이 같은 에셋 경로 해석을 사용한다.
function LuaScript.moduleLoader(project, registry)
    local modules, loadingModules = {}, {}
    local moduleRequire
    local function environment()
        return setmetatable({require = moduleRequire}, {__index = _G})
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
        if modules[reference] ~= nil then return modules[reference] end
        assert(not loadingModules[reference], "Project module cycle: " .. reference)
        loadingModules[reference] = true
        local ok, value = pcall(function()
            local bytes = assert(project:readSource(reference))
            local chunk = assert(loadstring(bytes, "@" .. reference))
            setfenv(chunk, environment())
            return chunk()
        end)
        loadingModules[reference] = nil
        assert(ok, value)
        modules[reference] = value == nil and true or value
        return modules[reference]
    end
    return moduleRequire
end

-- 검증용 프로젝트 뷰는 원본 레지스트리의 로딩 캐시를 공유하지 않는다.
function LuaScript.loader(project)
    if project then
        project.plugins = project.plugins or require("project.PluginRegistry").new(project,
            not project.rootPath and {manifests = {}, enabled = {}} or nil)
        if project.plugins.project ~= project then project.plugins = project.plugins:forProject(project) end
    end
    local loaded, visiting = {}, {}
    local moduleRequire = project and LuaScript.moduleLoader(project, project.plugins) or require
    local function environment()
        return setmetatable({require = moduleRequire}, {__index = _G})
    end
    local function load(reference, expectedKind, depth)
        if expectedKind == "script" and (reference == "Script" or project.plugins and project.plugins.scripts[reference]) then
            return project.plugins:loadScript(reference)
        end
        local canonical, referenceError = project:getAssetReference(reference)
        if not canonical then return nil, referenceError end
        local pluginScript = project.plugins.assetScripts and project.plugins.assetScripts[canonical]
        if pluginScript then return project.plugins:loadScript(pluginScript) end
        local key = project:getAssetId(canonical) or canonical
        if visiting[key] then return nil, "Lua Class inheritance cycle: " .. canonical end
        if (depth or 0) > 64 then return nil, "Lua Class inheritance is too deep" end
        local kind, kindError = project:getScriptKind(key)
        if not kind then return nil, kindError end
        if expectedKind and kind ~= expectedKind then return nil, "Expected a " .. expectedKind .. " Lua Class" end
        if loaded[key] then return loaded[key] end
        local path, pathError = project:resolveSourceFile(key)
        if not path then return nil, pathError end
        local text, readError = project:readSource(key)
        if not text then return nil, readError end
        local chunk, compileError = loadstring(text, "@" .. canonical)
        if not chunk then return nil, compileError end
        setfenv(chunk, environment())
        local ok, class = pcall(chunk)
        if not ok then return nil, tostring(class) end
        if type(class) ~= "table" or getmetatable(class) then return nil, "Lua Class must return a plain table" end
        visiting[key] = true
        local function fail(err) visiting[key] = nil; return nil, err end
        local parent
        if class.extends ~= nil then
            if kind == "script" and (class.extends == "Script" or project.plugins and project.plugins.scripts[class.extends]) then
                local parentError
                parent, parentError = project.plugins:loadScript(class.extends)
                if not parent then return fail(parentError) end
            end
            if not parent and not Id.isValid(class.extends) then return fail("extends must be a script asset ID or built-in script") end
            local parentError
            if not parent then parent, parentError = load(class.extends, kind, (depth or 0) + 1) end
            if not parent then return fail(parentError) end
        end
        if kind == "script" then
            if class.build or class.load then return fail("Use beginPlay and owner:addScript; build/load callbacks are no longer supported") end
            parent = parent or require("core.Script")
            class.scriptType = canonical:match("([^/]+)%.lua$")
            local valid, script = pcall(parent.extend, parent, class)
            if not valid then return fail(tostring(script)) end
            classNames[script] = class.scriptType
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
        for _, name in ipairs({"build", "beginPlay", "load", "update"}) do
            if class[name] ~= nil and type(class[name]) ~= "function" then return fail(name .. " must be a function") end
        end
        -- 기존 load 선언도 자신의 beginPlay로 승격하여 새 부모와의 상속을 유지한다.
        if class.beginPlay == nil and class.load ~= nil then class.beginPlay = class.load end
        if class.load == nil and class.beginPlay ~= nil then class.load = class.beginPlay end
        class.properties, class.super = schema, parent
        classNames[class] = canonical:match("([^/]+)%.lua$") or canonical
        if parent then setmetatable(class, {__index = parent}) end
        loaded[key], visiting[key] = class, nil
        return class
    end
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
