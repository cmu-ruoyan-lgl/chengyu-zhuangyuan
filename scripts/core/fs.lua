-- 文本文件读写抽象。
-- 引擎运行时 io 库被移除，只能 File/fileSystem（且相对路径自动做项目+用户隔离）；
-- 离线跑 lua54 时没有 File，只有 io。本模块对上层屏蔽差异：
--   readText(path) -> string|nil
--   writeText(path, str) -> boolean
--   exists(path) -> boolean
-- 引擎内读只读数据（data/*.json）优先走 ResourceCache，因为随包 pak 里只有资源目录。

local M = {}

local hasIo = type(io) == "table" and type(io.open) == "function"

--- 判断当前是否在引擎运行时内。
--- 注意：wasm 端引擎全局绑定是 userdata 而非 table，禁止 type()=="table" 判断。
function M.inEngine()
    return _G.File ~= nil and _G.fileSystem ~= nil
end

--- data/ 资源的运行时路径。
--- 平台构建门禁规定 asset_dirs 只能是 ../assets 与 ../scripts，
--- 故数据文件物理上放在 assets/data/；assets 挂根后 fs_path 为 "data/xxx"。
--- 打包/引擎播放器（io 被移除）：返回 "data/"..rel（走 cache:GetFile）；
--- 离线 lua54 与本地 tool_mode（io 可用，直读项目根）：返回 "assets/data/"..rel。
function M.data(rel)
    if hasIo then
        return "assets/data/" .. rel
    end
    return "data/" .. rel
end

--- 读取文本文件；失败返回 nil 与原因
function M.readText(path)
    if hasIo then
        local f = io.open(path, "rb")
        if not f then return nil, "io.open 失败: " .. tostring(path) end
        local content = f:read("*a")
        f:close()
        return content
    end

    -- 引擎：先试资源目录（随包数据），再试用户沙箱（存档）。
    -- 引擎绑定是 userdata，不做 type 守卫，一律 pcall。
    if _G.cache then
        local ok, file = pcall(function() return _G.cache:GetFile(path) end)
        if ok and file then
            local okRead, content = pcall(function() return file:ReadString() end)
            pcall(function() file:Close() end)
            if okRead and type(content) == "string" and #content > 0 then
                return content
            end
        end
    end

    if _G.fileSystem and _G.File then
        local okEx, exists = pcall(function() return _G.fileSystem:FileExists(path) end)
        if okEx and exists then
            local okF, file = pcall(function() return _G.File(path, _G.FILE_READ) end)
            if okF and file then
                local okR, content = pcall(function()
                    if file:IsOpen() then return file:ReadString() end
                    return nil
                end)
                pcall(function() file:Close() end)
                if okR and type(content) == "string" and #content > 0 then
                    return content
                end
            end
        end
    end

    return nil, "引擎内未找到文件: " .. tostring(path)
end

--- 写入文本文件（引擎内走用户沙箱；离线走 io）
function M.writeText(path, str)
    if hasIo then
        local dir = path:match("^(.*)/[^/]+$")
        if dir then
            -- 离线工具允许建目录；pcall 防止平台差异
            pcall(function() os.execute('mkdir -p "' .. dir .. '"') end)
        end
        local f, err = io.open(path, "wb")
        if not f then return false, err end
        f:write(str)
        f:close()
        return true
    end

    local file = _G.File(path, _G.FILE_WRITE)
    if not file or not file:IsOpen() then
        return false, "File 打开失败: " .. tostring(path)
    end
    file:WriteString(str)
    file:Close()
    return true
end

--- 原子写：先写 .tmp 再 rename（存档防断电损坏）
function M.writeTextAtomic(path, str)
    local tmp = path .. ".tmp"
    local ok, err = M.writeText(tmp, str)
    if not ok then return false, err end
    if hasIo then
        local okRename, errRename = os.rename(tmp, path)
        return okRename and true or false, errRename
    end
    -- 引擎内 File 无 rename，改为写目标文件（配合 system/save.lua 的 .bak 备份）
    return M.writeText(path, str)
end

function M.exists(path)
    if hasIo then
        local f = io.open(path, "rb")
        if f then f:close(); return true end
        return false
    end
    if _G.fileSystem then
        local ok, res = pcall(function() return _G.fileSystem:FileExists(path) end)
        return ok and res == true
    end
    return false
end

return M
