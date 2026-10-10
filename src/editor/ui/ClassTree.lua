local Scrollbar = require("editor.ui.Scrollbar")
local FolderTree = require("editor.ui.FolderTree")
local Widget = require("editor.ui.Widget")
local Tree = setmetatable({}, {__index = FolderTree})
Tree.__index = Tree

function Tree.new(project, kind)
    local self = setmetatable(Widget.new(), Tree)
    self.project, self.kind, self.expanded, self.scroll = project, kind, {}, 0
    self.records, self.roots = {}, {}
    for _, base in ipairs(kind == "lua" and {"level", "lobject", "component"} or {kind == "level" and "level" or "lobject"}) do
        local key = "builtin:" .. base
        local node = {reference = key, name = base == "level" and "Level" or base == "component" and "LObjectComponent" or "LObject",
            kind = base, parentReference = base == "component" and "LObjectComponent" or nil, children = {}}
        self.records[key], self.roots[#self.roots + 1] = node, node
        self.expanded[key] = kind ~= "lua"
    end
    if kind == "lua" then
        local parents = {SceneComponent = "component", BoundsComponent = "SceneComponent", CameraComponent = "SceneComponent", RectComponent = "BoundsComponent", CanvasComponent = "RectComponent", RenderComponent = "BoundsComponent", SpriteComponent = "RenderComponent", PointerComponent = "BoundsComponent"}
        for _, name in ipairs({"SceneComponent", "BoundsComponent", "CameraComponent", "RectComponent", "CanvasComponent", "RenderComponent", "SpriteComponent", "PointerComponent"}) do
            local parent = self.records["builtin:" .. parents[name]]
            local node = {reference = "builtin:" .. name, name = name, kind = "component", parentReference = name, children = {}}
            node.parent = parent.reference
            self.records[node.reference] = node
            parent.children[#parent.children + 1] = node
        end
    end
    local loader = require("project.LuaClass").loader(project)
    for reference, meta in pairs(project.assetMetadata or {}) do
        local script = reference:match("^Sources/.+%.lua$") and meta.scriptKind
        local prefab = kind == "prefab" and reference:match("^Assets/.+%.prefab$")
        if script and self.records["builtin:" .. script] or prefab then
            local id = project:getAssetId(reference)
            local node = {reference = id, assetId = id, path = reference,
                name = reference:match("([^/]+)$"), kind = prefab and "lobject" or script, children = {}}
            if prefab then
                local bytes, err = project:readAsset(id)
                local data
                if bytes then data, err = require("project.Prefab").decode(bytes) end
                node.error = err
                if data then
                    node.parent = data.definitionReference and project:getAssetId(project:getAssetReference(data.definitionReference))
                    local definition
                    definition, node.error = require("project.ObjectDefinition").resolve(project, id, loader)
                    if definition then
                        local preview
                        preview, node.error = require("project.ObjectDefinition").inspectorTarget(project, {}, definition)
                    end
                end
            else
                local class
                class, node.error = loader(id, script)
                if class then
                    node.parent = class.extends
                    if script == "component" and self.records["builtin:" .. tostring(node.parent)] then node.parent = "builtin:" .. node.parent end
                end
            end
            self.records[id] = node
            self.expanded[id] = kind ~= "lua"
        end
    end
    for key, node in pairs(self.records) do
        if node.assetId then
            local parent = not node.error and node.parent and self.records[node.parent]
                or self.records["builtin:" .. node.kind]
            parent.children[#parent.children + 1] = node
        end
    end
    local function sort(node)
        table.sort(node.children, function(a, b)
            if a.name == b.name then return a.path < b.path end
            return a.name:lower() < b.name:lower()
        end)
        for _, child in ipairs(node.children) do sort(child) end
    end
    for _, node in ipairs(self.roots) do sort(node) end
    self.selected = self.roots[1].reference
    self.scrollbar = Scrollbar.new(function() return self.scroll end,
        function(value) self.scroll = math.floor(value + 0.5) end)
    self:rebuild()
    return self
end

function Tree:rebuild()
    self.nodes = {}
    local function visit(node, depth)
        node.depth = depth
        self.nodes[#self.nodes + 1] = node
        if self.expanded[node.reference] then
            for _, child in ipairs(node.children) do visit(child, depth + 1) end
        end
    end
    for _, node in ipairs(self.roots) do visit(node, 0) end
    self:clampScroll()
end

function Tree:choose(node)
    if not node then return end
    local parent = not node.error and node.parent or (node.assetId and "builtin:" .. node.kind)
    local visited = {}
    while parent do
        if visited[parent] then break end
        visited[parent] = true
        self.expanded[parent] = true
        local record = self.records[parent]
        parent = record and (not record.error and record.parent or record.assetId and "builtin:" .. record.kind)
    end
    self:rebuild()
    self.selected, self.error = node.reference, node.error
    if self.onSelect then self.onSelect(node) end
end

function Tree:selection() return self.records[self.selected] end
return Tree
