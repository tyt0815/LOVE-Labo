local Failure = {}
function Failure:load() error("Intentional destination initialization failure") end
return Failure
