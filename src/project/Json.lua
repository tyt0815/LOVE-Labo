local Json = {}

local ARRAY_METATABLE = {}
local NULL = {}

Json.null = NULL

function Json.array(values)
    return setmetatable(values or {}, ARRAY_METATABLE)
end

local function isArray(value)
    if getmetatable(value) == ARRAY_METATABLE then
        return true
    end

    local count = 0
    local maximum = 0

    for key in pairs(value) do
        if type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
        then
            return false
        end

        count = count + 1

        if key > maximum then
            maximum = key
        end
    end

    -- 빈 table은 object와 array를 구분할 정보가 없으므로
    -- Json.array()로 명시된 경우에만 빈 array로 취급한다.
    return count > 0 and maximum == count
end

local ESCAPE_MAP = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t"
}

local function encodeString(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        local escaped = ESCAPE_MAP[character]

        if escaped then
            return escaped
        end

        return string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function encodeValue(value, pretty, depth, seen)
    if value == NULL then
        return "null"
    end

    local valueType = type(value)

    if valueType == "nil" then
        return "null"
    end

    if valueType == "boolean" then
        return value and "true" or "false"
    end

    if valueType == "number" then
        if value ~= value
            or value == math.huge
            or value == -math.huge
        then
            error("cannot encode non-finite number", 0)
        end

        return tostring(value)
    end

    if valueType == "string" then
        return encodeString(value)
    end

    if valueType ~= "table" then
        error("cannot encode value of type " .. valueType, 0)
    end

    if seen[value] then
        error("cannot encode cyclic table", 0)
    end

    seen[value] = true

    local indent = pretty and string.rep("  ", depth) or ""
    local childIndent = pretty and string.rep("  ", depth + 1) or ""
    local separator = pretty and ",\n" or ","
    local colon = pretty and ": " or ":"

    local result

    if isArray(value) then
        local items = {}

        for i = 1, #value do
            items[i] = childIndent
                .. encodeValue(value[i], pretty, depth + 1, seen)
        end

        if #items == 0 then
            result = "[]"
        elseif pretty then
            result = "[\n"
                .. table.concat(items, separator)
                .. "\n"
                .. indent
                .. "]"
        else
            result = "[" .. table.concat(items, separator) .. "]"
        end
    else
        local keys = {}

        for key in pairs(value) do
            if type(key) ~= "string" then
                error("JSON object keys must be strings", 0)
            end

            keys[#keys + 1] = key
        end

        -- 저장할 때마다 key 순서가 바뀌어 Git diff가 생기지 않도록
        -- object key를 항상 정렬한다.
        table.sort(keys)

        local items = {}

        for i, key in ipairs(keys) do
            items[i] = childIndent
                .. encodeString(key)
                .. colon
                .. encodeValue(value[key], pretty, depth + 1, seen)
        end

        if #items == 0 then
            result = "{}"
        elseif pretty then
            result = "{\n"
                .. table.concat(items, separator)
                .. "\n"
                .. indent
                .. "}"
        else
            result = "{" .. table.concat(items, separator) .. "}"
        end
    end

    seen[value] = nil

    return result
end

function Json.encode(value, pretty)
    local ok, result = pcall(
        encodeValue,
        value,
        pretty == true,
        0,
        {}
    )

    if not ok then
        return nil, result
    end

    return result
end

local function utf8FromCodepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end

    if codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    if codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + (math.floor(codepoint / 0x40) % 0x40),
            0x80 + (codepoint % 0x40)
        )
    end

    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + (math.floor(codepoint / 0x1000) % 0x40),
        0x80 + (math.floor(codepoint / 0x40) % 0x40),
        0x80 + (codepoint % 0x40)
    )
end

local function createDecoder(text)
    local decoder = {
        text = text,
        position = 1,
        length = #text
    }

    function decoder:fail(message)
        error(
            string.format(
                "JSON decode error at byte %d: %s",
                self.position,
                message
            ),
            0
        )
    end

    function decoder:skipWhitespace()
        while self.position <= self.length do
            local byte = string.byte(self.text, self.position)

            if byte ~= 32
                and byte ~= 9
                and byte ~= 10
                and byte ~= 13
            then
                break
            end

            self.position = self.position + 1
        end
    end

    function decoder:parseUnicodeEscape()
        local hex = self.text:sub(
            self.position,
            self.position + 3
        )

        if #hex ~= 4 or not hex:match("^%x%x%x%x$") then
            self:fail("invalid unicode escape")
        end

        self.position = self.position + 4

        local codepoint = tonumber(hex, 16)

        if codepoint >= 0xD800 and codepoint <= 0xDBFF then
            if self.text:sub(
                self.position,
                self.position + 1
            ) ~= "\\u" then
                self:fail("missing low surrogate")
            end

            self.position = self.position + 2

            local lowHex = self.text:sub(
                self.position,
                self.position + 3
            )

            if #lowHex ~= 4
                or not lowHex:match("^%x%x%x%x$")
            then
                self:fail("invalid low surrogate")
            end

            self.position = self.position + 4

            local low = tonumber(lowHex, 16)

            if low < 0xDC00 or low > 0xDFFF then
                self:fail("invalid low surrogate")
            end

            codepoint =
                0x10000
                + (codepoint - 0xD800) * 0x400
                + (low - 0xDC00)
        elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
            self:fail("unexpected low surrogate")
        end

        return utf8FromCodepoint(codepoint)
    end

    function decoder:parseString()
        if self.text:sub(self.position, self.position) ~= '"' then
            self:fail("expected string")
        end

        self.position = self.position + 1

        local parts = {}

        while self.position <= self.length do
            local character = self.text:sub(
                self.position,
                self.position
            )

            if character == '"' then
                self.position = self.position + 1
                return table.concat(parts)
            end

            if character == "\\" then
                self.position = self.position + 1

                local escape = self.text:sub(
                    self.position,
                    self.position
                )

                local simple = {
                    ['"'] = '"',
                    ["\\"] = "\\",
                    ["/"] = "/",
                    ["b"] = "\b",
                    ["f"] = "\f",
                    ["n"] = "\n",
                    ["r"] = "\r",
                    ["t"] = "\t"
                }

                if simple[escape] then
                    parts[#parts + 1] = simple[escape]
                    self.position = self.position + 1
                elseif escape == "u" then
                    self.position = self.position + 1
                    parts[#parts + 1] =
                        self:parseUnicodeEscape()
                else
                    self:fail("invalid string escape")
                end
            else
                local byte = string.byte(
                    self.text,
                    self.position
                )

                if byte < 32 then
                    self:fail(
                        "unescaped control character in string"
                    )
                end

                parts[#parts + 1] = character
                self.position = self.position + 1
            end
        end

        self:fail("unterminated string")
    end

    function decoder:parseNumber()
        local start = self.position

        if self.text:sub(
            self.position,
            self.position
        ) == "-" then
            self.position = self.position + 1
        end

        local first = self.text:sub(
            self.position,
            self.position
        )

        if first == "0" then
            self.position = self.position + 1
        elseif first:match("[1-9]") then
            repeat
                self.position = self.position + 1
            until not self.text:sub(
                self.position,
                self.position
            ):match("%d")
        else
            self:fail("invalid number")
        end

        if self.text:sub(
            self.position,
            self.position
        ) == "." then
            self.position = self.position + 1

            if not self.text:sub(
                self.position,
                self.position
            ):match("%d") then
                self:fail("invalid number fraction")
            end

            repeat
                self.position = self.position + 1
            until not self.text:sub(
                self.position,
                self.position
            ):match("%d")
        end

        local exponent = self.text:sub(
            self.position,
            self.position
        )

        if exponent == "e" or exponent == "E" then
            self.position = self.position + 1

            local sign = self.text:sub(
                self.position,
                self.position
            )

            if sign == "+" or sign == "-" then
                self.position = self.position + 1
            end

            if not self.text:sub(
                self.position,
                self.position
            ):match("%d") then
                self:fail("invalid number exponent")
            end

            repeat
                self.position = self.position + 1
            until not self.text:sub(
                self.position,
                self.position
            ):match("%d")
        end

        local numberText = self.text:sub(
            start,
            self.position - 1
        )
        local value = tonumber(numberText)

        if value == nil then
            self:fail("invalid number")
        end

        return value
    end

    function decoder:parseArray()
        self.position = self.position + 1
        self:skipWhitespace()

        local result = Json.array({})

        if self.text:sub(
            self.position,
            self.position
        ) == "]" then
            self.position = self.position + 1
            return result
        end

        while true do
            result[#result + 1] = self:parseValue()
            self:skipWhitespace()

            local character = self.text:sub(
                self.position,
                self.position
            )

            if character == "]" then
                self.position = self.position + 1
                return result
            end

            if character ~= "," then
                self:fail("expected ',' or ']'")
            end

            self.position = self.position + 1
            self:skipWhitespace()
        end
    end

    function decoder:parseObject()
        self.position = self.position + 1
        self:skipWhitespace()

        local result = {}

        if self.text:sub(
            self.position,
            self.position
        ) == "}" then
            self.position = self.position + 1
            return result
        end

        while true do
            if self.text:sub(
                self.position,
                self.position
            ) ~= '"' then
                self:fail("expected object key")
            end

            local key = self:parseString()

            if result[key] ~= nil then
                self:fail("duplicate object key")
            end

            self:skipWhitespace()

            if self.text:sub(
                self.position,
                self.position
            ) ~= ":" then
                self:fail("expected ':'")
            end

            self.position = self.position + 1
            self:skipWhitespace()

            result[key] = self:parseValue()
            self:skipWhitespace()

            local character = self.text:sub(
                self.position,
                self.position
            )

            if character == "}" then
                self.position = self.position + 1
                return result
            end

            if character ~= "," then
                self:fail("expected ',' or '}'")
            end

            self.position = self.position + 1
            self:skipWhitespace()
        end
    end

    function decoder:parseValue()
        self:skipWhitespace()

        local character = self.text:sub(
            self.position,
            self.position
        )

        if character == '"' then
            return self:parseString()
        end

        if character == "{" then
            return self:parseObject()
        end

        if character == "[" then
            return self:parseArray()
        end

        if character == "-"
            or character:match("%d")
        then
            return self:parseNumber()
        end

        local remaining = self.text:sub(self.position)

        if remaining:sub(1, 4) == "true" then
            self.position = self.position + 4
            return true
        end

        if remaining:sub(1, 5) == "false" then
            self.position = self.position + 5
            return false
        end

        if remaining:sub(1, 4) == "null" then
            self.position = self.position + 4
            return NULL
        end

        self:fail("unexpected token")
    end

    return decoder
end

function Json.decode(text)
    if type(text) ~= "string" then
        return nil, "JSON input must be a string"
    end

    local decoder = createDecoder(text)

    local ok, value = pcall(function()
        local result = decoder:parseValue()
        decoder:skipWhitespace()

        if decoder.position <= decoder.length then
            decoder:fail("trailing data")
        end

        return result
    end)

    if not ok then
        return nil, value
    end

    return value
end

return Json
