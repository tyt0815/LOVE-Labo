local Spawner = {}

function Spawner.bind(project, world, loadClass)
    local depth = 0
    local loadTemplate = require("project.LObjectTemplate").loader(project, loadClass)
    world.spawnLObjectFactory = function(reference, transform, overrides)
        if depth >= 64 then return nil, "Spawn nesting is too deep" end
        local checkpoint = #world.lobjects
        depth = depth + 1
        local called, object, err = pcall(function()
            local template, templateError = loadTemplate(reference)
            if not template then return nil, templateError end
            local initialTransform, transformError = require("core.Transform").copy(transform or {x = 0, y = 0})
            if not initialTransform then return nil, transformError end
            overrides = overrides or {}
            if type(overrides) ~= "table" then return nil, "Spawn overrides must be a table" end
            local instance, createError = require("core.LObject").new(world.nextRuntimeId,
                {transform = initialTransform, definitionReference = template.reference})
            if not instance then return nil, createError end
            local base, used = template.name, {}
            for _, existing in ipairs(world.lobjects) do if existing.name then used[existing.name] = true end end
            local number = 1; while used[base .. " " .. number] do number = number + 1 end
            instance.name = base .. " " .. number
            world.nextRuntimeId = world.nextRuntimeId + 1
            world.lobjects[#world.lobjects + 1] = instance
            local objects, configureError = require("runtime.TemplateObjects").configure(world, template.hierarchy, instance, overrides)
            if not objects then return nil, configureError end
            local valid, propertyError = require("runtime.TemplateObjects").resolveReferences(project, world)
            if not valid then return nil, propertyError end
            for _, node in ipairs(template.hierarchy.nodes) do
                local begun, beginError = objects[node.path]:beginPlay(world)
                if not begun then return nil, beginError end
            end
            return instance
        end)
        depth = depth - 1
        if not called or not object then
            -- 실패한 초기화와 그 안에서 생성한 객체를 함께 제거한다. ID는 재사용하지 않는다.
            for i = #world.lobjects, checkpoint + 1, -1 do world.lobjects[i] = nil end
            return nil, called and err or tostring(object)
        end
        return object
    end
end
return Spawner
