local ClassName = {}
function ClassName.fromModule(name, fallback)
    local identifier = (name or fallback):gsub("\\", "/"):match("([^/]+)$"):gsub("%.[Ll][Uu][Aa]$", "")
    -- 구분자를 제거하고 각 단어의 첫 글자를 대문자로 만들어 파일·클래스 이름을 통일한다.
    local words = {}
    for word in identifier:gmatch("[%w]+") do words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2) end
    identifier = table.concat(words)
    if identifier == "" then return fallback end
    if identifier:match("^%d") then identifier = "Class" .. identifier end
    return identifier
end
return ClassName
