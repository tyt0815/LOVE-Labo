local Id = require("project.AssetId")
local LuaClass = {}
local classNames = setmetatable({}, {__mode = "k"})
-- 클래스 테이블에 Editor 필드를 추가하지 않고 현재 모듈 이름을 별도로 보관한다.
function LuaClass.name(class) return classNames[class] end

function LuaClass.validValue(kind, value)
    return require("core.PropertySchema").validValue(kind, value)
end

-- 한 로드 범위 안에서만 클래스를 공유한다. 다음 검사·Play에서는 소스를 다시 읽는다.
function LuaClass.loader(project)
    local loaded, visiting = {}, {}
    local function load(reference, expectedKind, depth)
        local canonical, referenceError = project:getAssetReference(reference)
        if not canonical then return nil, referenceError end
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
        setfenv(chunk, setmetatable({}, {__index = _G}))
        local ok, class = pcall(chunk)
        if not ok then return nil, tostring(class) end
        if type(class) ~= "table" or getmetatable(class) then return nil, "Lua Class must return a plain table" end
        visiting[key] = true
        local function fail(err) visiting[key] = nil; return nil, err end
        local parent
        if class.extends ~= nil then
            local builtins = kind == "component" and require("Engine") or {}
            parent = builtins[class.extends]
            if parent and class.extends ~= "LObjectComponent" and class.extends ~= "SceneComponent" and class.extends ~= "RenderComponent" and class.extends ~= "SpriteComponent" then parent = nil end
            if not parent and not Id.isValid(class.extends) then return fail("extends must be a Lua Class asset ID or built-in Component") end
            local parentError
            if not parent then parent, parentError = load(class.extends, kind, (depth or 0) + 1) end
            if not parent then return fail(parentError) end
        end
        if kind == "component" then
            parent = parent or require("core.LObjectComponent")
            class.componentType = canonical:match("([^/]+)%.lua$")
            local extended, component = pcall(parent.extend, parent, class)
            if not extended then return fail(tostring(component)) end
            for _, name in ipairs({"build", "beginPlay", "load", "update", "draw", "getLocalBounds"}) do
                if component[name] ~= nil and type(component[name]) ~= "function" then return fail(name .. " must be a function") end
            end
            classNames[component] = class.componentType
            loaded[key], visiting[key] = component, nil
            return component
        end
        local schema = {}
        for name, declaration in pairs(parent and parent.properties or {}) do schema[name] = declaration end
        if class.properties ~= nil and type(class.properties) ~= "table" then return fail("properties must be a table") end
        for name, declaration in pairs(class.properties or {}) do
            if type(name) ~= "string" or name == "" or type(declaration) ~= "table"
                or not LuaClass.validValue(declaration.type, declaration.default) then
                return fail("Invalid property declaration: " .. tostring(name))
            end
            if schema[name] and schema[name].type ~= declaration.type then return fail("Inherited property type cannot change: " .. name) end
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

function LuaClass.load(project, reference, kind)
    return LuaClass.loader(project)(reference, kind)
end

function LuaClass.values(class, overrides)
    if overrides ~= nil and type(overrides) ~= "table" then return nil, "Property overrides must be an object" end
    local values = {}
    for name, declaration in pairs(class and class.properties or {}) do values[name] = declaration.default end
    for name, value in pairs(overrides or {}) do
        local declaration = class and class.properties[name]
        if not declaration or not LuaClass.validValue(declaration.type, value) then return nil, "Invalid property override: " .. tostring(name) end
        values[name] = value
    end
    return values
end

function LuaClass.compatibleOverrides(class, overrides)
    local result = {}
    for name, value in pairs(overrides or {}) do
        local declaration = class and class.properties[name]
        if declaration and LuaClass.validValue(declaration.type, value) and value ~= declaration.default then result[name] = value end
    end
    return result
end
return LuaClass
