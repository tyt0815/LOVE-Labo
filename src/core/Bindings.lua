local Bindings = {}
function Bindings.live(owner)
    return owner and owner.owner and owner.owner.scripts[owner.id] == owner and not owner.owner.removing and not owner.hasUnloaded and owner.enabled ~= false
end
function Bindings.add(owner, cleanup)
    assert(owner and owner.owner and type(cleanup) == "function", "Binding requires an attached Script owner")
    local handle = {owner = owner}
    function handle:release()
        if self.released then return end
        assert(not self.transferPending, "Binding owner is being transferred")
        self.released = true; cleanup()
    end
    owner.bindingHandles = owner.bindingHandles or {}
    owner.bindingHandles[#owner.bindingHandles + 1] = handle
    return handle
end
function Bindings.release(owner)
    local pending = owner.bindingHandles or {}; owner.bindingHandles = nil
    for index = #pending, 1, -1 do pending[index]:release() end
end
return Bindings
