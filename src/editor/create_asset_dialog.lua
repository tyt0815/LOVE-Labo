local Dialog = require("editor.ui.dialog")
local FolderTree = require("editor.ui.folder_tree")
local ClassTree = require("editor.ui.class_tree")
local Create = {}

function Create.show(browser, folder, kind)
    local project, root = browser.project, browser.uiRoot
    local titles = {folder = "Folder", level = "Level", prefab = "Prefab", lua = "Lua Class"}
    local defaults = {folder = "NewFolder", level = "L_", prefab = "PF_", lua = "NewClass"}
    local pathRoot = kind == "lua" and "Sources" or kind == "folder" and folder:match("^[^/]+") or "Assets"
    if folder ~= pathRoot and folder:sub(1, #pathRoot + 1) ~= pathRoot .. "/" then folder = pathRoot end
    local state = {folder = folder, name = defaults[kind]}
    local parentTree = kind ~= "folder" and ClassTree.new(project, kind)
    local showParent, showLocation

    showLocation = function()
        local dialog
        local folders = FolderTree.new(project, pathRoot, nil, state.folder, function(selected)
            state.folder = selected
            dialog.options.message, dialog.error = selected, nil
        end)
        dialog = Dialog.new(root, {title = "New " .. titles[kind] .. " - Location and Name",
            message = state.folder, input = true, value = state.name, content = folders,
            contentHint = "Tab: name/tree    Arrows: navigate folders", confirmLabel = "Create",
            onBack = parentTree and function()
                dialog.text, dialog.replace = require("editor.ui.ime").finish(dialog, dialog.text, dialog.replace)
                state.name = dialog.text
                showParent()
            end or nil,
            onConfirm = function(name)
                local options = {}
                if parentTree then
                    local parent = parentTree:selection()
                    if not parent or parent.error then return false, parent and parent.error or "Choose a parent" end
                    if kind == "lua" then options = {scriptKind = parent.kind, parentReference = parent.assetId}
                    else options = {scriptReference = parent.assetId} end
                end
                local ok, reference
                if browser.assetOperations then ok, reference = browser.assetOperations:create(state.folder, kind, name, options)
                else ok, reference = project:createEntry(state.folder, kind, name, options) end
                if not ok then return false, reference end
                browser:refresh(true)
                browser:openFolder(state.folder)
                browser.selectedReference = reference
                return true
            end})
        dialog.error = folders.error
        -- 접두사를 선택하지 않고 뒤에 이어 입력한다. 폴더 선택 후 Tab으로도 이름에 돌아온다.
        dialog.contentFocused = false
        dialog.replace = kind ~= "level" and kind ~= "prefab"
        require("editor.ui.text_edit").begin(dialog, dialog.text, dialog.replace)
    end

    showParent = function()
        local dialog
        parentTree.onSelect = function(node)
            dialog.options.message = node.path or node.name
            dialog.error = node.error
        end
        local selected = parentTree:selection()
        dialog = Dialog.new(root, {title = "New " .. titles[kind] .. " - Parent",
            message = selected.path or selected.name, content = parentTree,
            contentHint = "Arrows: select, expand or collapse    Enter: next", confirmLabel = "Next",
            onConfirm = function()
                local parent = parentTree:selection()
                if not parent or parent.error then return false, parent and parent.error or "Choose a parent" end
                showLocation()
                return true
            end})
        dialog.error = selected.error
    end
    if parentTree then showParent() else showLocation() end
end
return Create
