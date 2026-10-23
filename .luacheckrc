-- luacheck 配置（Lua 5.4，与 UrhoXRuntime 内嵌版本一致）
std = "lua54"

-- 引擎在运行时注入大量全局符号（无法静态枚举）。
-- 规则：遇到 113（accessing undefined variable）先确认是真拼写错误，
-- 还是引擎全局；确认是引擎全局的，加入下方 globals 白名单，不要直接 ignore 113。
globals = {
    -- 引擎入口约定（UrhoXRuntime 调用）
    "Start", "Stop",
    -- NanoVG（引擎注册的全局 C API）
    "nvgCreate", "nvgDelete", "nvgCreateFont", "nvgBeginFrame", "nvgEndFrame",
    "nvgFontSize", "nvgFontFaceId", "nvgFillColor", "nvgRGBA", "nvgText",
    "nvgFontFace",
    -- 引擎子系统（core/fs.lua 里做能力探测用）
    "File", "fileSystem", "cache", "graphics", "FILE_READ", "FILE_WRITE",
    "SCAN_FILES", "SCAN_DIRS", "SCAN_ALL",
    -- 引擎子系统（S1 新增：权威时间 / 音频 / 云存档）
    "common", "Scene", "clientCloud",
    -- 引擎 JSON（core/json.lua 优先走 cjson）
    "cjson",
}

-- 每行长度不限制（UI 布局代码天然长行）
max_line_length = false

ignore = {
    "212", -- unused argument（回调签名由引擎规定，参数常不用）
    "213", -- unused loop variable
}

exclude_files = {
    ".cli",
    ".tmp",
    "urhox-libs",
    "engine-docs",
}
