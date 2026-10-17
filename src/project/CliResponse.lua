local Json = require("project.Json")
local Response = {}
-- 결과 파일 저장까지 끝난 뒤에만 호스트가 최종 응답과 종료 코드를 출력한다.
function Response.finish(ok, result, save)
    local response = {version = 1, ok = ok}
    if ok then response.result = result else response.error = tostring(result) end
    local bytes, encodeError = Json.encode(response)
    if not bytes then
        ok = false
        bytes = assert(Json.encode({version = 1, ok = false, error = "Cannot encode command result: " .. tostring(encodeError)}))
    end
    if save then
        local called, saved, err = pcall(save, bytes .. "\n")
        if not called or not saved then
            ok = false
            bytes = assert(Json.encode({version = 1, ok = false, error = tostring(called and err or saved)}))
        end
    end
    return bytes, ok
end
return Response
