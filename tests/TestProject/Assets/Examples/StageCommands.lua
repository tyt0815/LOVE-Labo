local Model = require("Examples.StageModel")
local function workspace(context) return assert(context.workspace, "Specify --workspace <absolute content folder>") end
return {summary = "Stage editor commands. The game and CLI share StageModel.", commands = {
    create = {summary = "Create a stage without replacing an existing file.", parameters = {
        file = {type = "string", default = "Stage.json"}, name = {type = "string", required = true}},
        run = function(context, args)
            return {revision = workspace(context):writeJson(args.file, Model.new(args.name), false)}
        end},
    inspect = {summary = "Read and validate a stage.", parameters = {file = {type = "string", default = "Stage.json"}},
        run = function(context, args)
            local data, revision = workspace(context):readJson(args.file)
            return {data = Model.validate(data), revision = revision}
        end},
    add = {summary = "Append a note, optionally checking the last observed revision.", parameters = {
        file = {type = "string", default = "Stage.json"}, beat = {type = "number", required = true},
        lane = {type = "integer", required = true}, revision = {type = "string"}},
        run = function(context, args)
            local target = workspace(context)
            local data, revision = target:readJson(args.file)
            assert(not args.revision or args.revision == revision, "Revision conflict")
            Model.add(data, args.beat, args.lane)
            return {revision = target:writeJson(args.file, data, revision), notes = #data.notes}
        end},
}}
