local M = {}

M.file_exists = function(file)
    local f = io.open(vim.fs.normalize(file), "r")

    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

return M
