local M = {}

M.file_exists = function(file)
    return vim.uv.fs_stat(file) ~= nil
end

return M
