local IME = {}
local ignored = {}

function IME.update()
    -- 수동 확정 뒤 같은 이벤트 묶음에 남은 OS 확정 입력만 무시한다.
    ignored = {}
end

function IME.consume(text)
    for index, value in ipairs(ignored) do
        if value == text then table.remove(ignored, index); return true end
    end
    return false
end

function IME.edited(owner, text)
    owner.composition = text ~= "" and text or nil
end

function IME.display(owner, text, replace)
    return owner.composition and ((replace and "" or text) .. owner.composition) or text
end

function IME.input(owner, value, text, replace)
    if IME.consume(text) then return value, replace end
    owner.composition = nil
    return (replace and "" or value) .. text, false
end

local function reset(owner)
    local text = owner.composition
    owner.composition = nil
    if text then
        ignored[#ignored + 1] = text
        -- 이전 필드의 조합을 끝내 다음 필드에 이어 붙지 않게 한다.
        local enabled = love.keyboard.hasTextInput()
        love.keyboard.setTextInput(false)
        if enabled then love.keyboard.setTextInput(true) end
    end
end

function IME.finish(owner, text, replace)
    if not owner.composition then return text, replace end
    text = IME.display(owner, text, replace)
    reset(owner)
    return text, false
end

function IME.cancel(owner)
    reset(owner)
end

function IME.handlesKey(owner, key)
    -- 자모 삭제·스페이스·일반 키는 IME가 처리하고 확정 이벤트로 반영한다.
    return owner.composition ~= nil and key ~= "return" and key ~= "kpenter"
        and key ~= "escape" and not IME.endsComposition(key)
end

function IME.endsComposition(key)
    return key == "tab" or key == "left" or key == "right" or key == "up" or key == "down"
        or love.keyboard.isDown("lctrl", "rctrl") and (key == "a" or key == "c" or key == "v")
end

return IME
