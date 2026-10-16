local Json = require("project.Json")
local Commands = {}
local TYPES = {string = true, number = true, integer = true, boolean = true, object = true, array = true}

local function validate(kind, value)
    if value == Json.null then return false end
    if kind == "integer" then return type(value) == "number" and value == value and value % 1 == 0 end
    if kind == "number" then return type(value) == "number" and value == value and math.abs(value) ~= math.huge end
    if kind == "array" then
        if type(value) ~= "table" then return false end
        local count = 0
        for key in pairs(value) do if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end; count = count + 1 end
        return count == #value
    end
    if kind == "object" then
        if type(value) ~= "table" then return false end
        for key in pairs(value) do if type(key) ~= "string" then return false end end
        return true
    end
    return type(value) == kind
end

function Commands.validateRequest(request)
    assert(type(request) == "table" and request ~= Json.null and type(request.command) == "string"
        and request.command ~= "", "Expected a command request")
    assert(request.arguments == nil or validate("object", request.arguments), "Expected arguments object")
    for _, name in ipairs({"workspace", "request", "result"}) do
        local path = request[name]
        assert(path == nil or type(path) == "string" and path ~= "" and not path:find("%z"), "Invalid host option: " .. name)
    end
    return request
end

function Commands.describe(definition)
    assert(type(definition) == "table" and type(definition.commands) == "table", "CLI entry must return {commands = {...}}")
    local result = {summary = definition.summary or "", commands = {}}
    for name, command in pairs(definition.commands) do
        assert(type(name) == "string" and name:match("^[a-z][%w.-]*$") and name ~= "help" and name ~= "schema", "Invalid command name")
        assert(type(command) == "table" and type(command.run) == "function", "Command requires run(context, arguments): " .. name)
        local data = {summary = command.summary or "", parameters = {}}
        for key, field in pairs(command.parameters or {}) do
            assert(type(key) == "string" and key:match("^[a-z][%w-]*$") and key ~= "workspace" and key ~= "request" and key ~= "result"
                and type(field) == "table" and TYPES[field.type], "Invalid parameter schema")
            assert(field.default == nil or validate(field.type, field.default), "Invalid parameter default")
            data.parameters[key] = {type = field.type, required = field.required == true, default = field.default, description = field.description or ""}
        end
        result.commands[name] = data
    end
    return result
end

function Commands.execute(definition, request, context)
    Commands.validateRequest(request)
    local schema = Commands.describe(definition)
    if request.command == "help" or request.command == "schema" then return schema end
    local command = assert(definition.commands[request.command], "Unknown command: " .. request.command)
    local fields, args = command.parameters or {}, {}
    assert(request.arguments == nil or type(request.arguments) == "table", "Expected arguments object")
    for name in pairs(request.arguments or {}) do assert(fields[name], "Unknown parameter: " .. tostring(name)) end
    for name, field in pairs(fields) do
        local value = (request.arguments or {})[name]
        if request.textArguments and type(value) == "string" and field.type ~= "string" then
            if field.type == "number" or field.type == "integer" then value = tonumber(value)
            else
                local decoded, err = Json.decode(value)
                assert(decoded ~= nil, err or "Invalid parameter: " .. name); value = decoded
            end
            assert(value ~= nil, "Invalid parameter: " .. name)
        end
        if value == nil then value = field.default end
        assert(value ~= nil or not field.required, "Missing parameter: " .. name)
        assert(value == nil or validate(field.type, value), "Invalid parameter: " .. name .. " (" .. field.type .. ")")
        args[name] = value
    end
    return command.run(context or {}, args)
end

function Commands.parse(args)
    local request = {command = "help", arguments = {}, textArguments = true}
    local index = 1
    if args[1] and args[1]:sub(1, 2) ~= "--" then request.command, index = args[1], 2 end
    while index <= #args do
        local option = assert(args[index]:match("^%-%-([%w-]+)$"), "Expected --parameter value")
        local value = assert(args[index + 1], "Missing value for --" .. option)
        if option == "workspace" or option == "request" or option == "result" then
            assert(request[option] == nil, "Duplicate option: " .. option); request[option] = value
        else
            assert(request.arguments[option] == nil, "Duplicate parameter: " .. option); request.arguments[option] = value
        end
        index = index + 2
    end
    if request.request then
        local original = request
        request = assert(Json.decode(assert(require("project.NativeFileSystem").read(original.request))))
        assert(type(request) == "table", "Request must be a JSON object")
        request.textArguments = false
        request.workspace = original.workspace or request.workspace
        request.result = original.result or request.result
    end
    return Commands.validateRequest(request)
end
return Commands
