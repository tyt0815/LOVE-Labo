local Id = {}
function Id.isValid(value)
    return type(value) == "string" and (value:match("^[%a_][%w_]*$") ~= nil
        or value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil)
end
return Id
