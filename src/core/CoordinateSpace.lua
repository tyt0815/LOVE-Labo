-- 좌표 변환은 모든 객체에 동일한 Transform API를 적용한다.
local Space = {}
function Space.transform(script, context) return script.owner:getWorldTransform(context) end
return Space
