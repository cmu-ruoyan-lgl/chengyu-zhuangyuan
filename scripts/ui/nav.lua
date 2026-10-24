-- 页面导航栈（UrhoX 单根 UI，页面即整屏替换）。
-- 用法：Nav.reset("home") 清栈直达；Nav.go("court") 入栈；Nav.back() 返回上一页。
-- 栈空时 back() 兜底回主页。页面模块按名懒加载，避免循环 require。

local Nav = { stack = {} }

local PAGES = {
    home  = "ui.pages.home",
    play  = "ui.pages.play",
    court = "ui.pages.court",
    shop  = "ui.pages.shop",
    book  = "ui.pages.book",
    login = "ui.pages.login",
}

local function mountTop()
    local top = Nav.stack[#Nav.stack]
    if not top then return nil end
    local modName = PAGES[top.name]
    if not modName then
        print("[nav] 未知页面: " .. tostring(top.name))
        return nil
    end
    local ok, mod = pcall(require, modName)
    if not ok or type(mod) ~= "table" or not mod.mount then
        print("[nav] 页面加载失败: " .. top.name .. " - " .. tostring(mod))
        return nil
    end
    return mod.mount(nil, top.opts)
end

--- 清栈直达（登录完成、回主页、开始闯关等「换场景」用）
function Nav.reset(name, opts)
    Nav.stack = { { name = name, opts = opts } }
    return mountTop()
end

--- 入栈跳转（主页 → 府邸/图鉴/商店 等「下钻」用）
function Nav.go(name, opts)
    Nav.stack[#Nav.stack + 1] = { name = name, opts = opts }
    return mountTop()
end

--- 返回上一页；栈空时回主页
function Nav.back()
    if #Nav.stack > 1 then
        Nav.stack[#Nav.stack] = nil
    else
        Nav.stack = { { name = "home" } }
    end
    return mountTop()
end

--- 当前页名
function Nav.current()
    local top = Nav.stack[#Nav.stack]
    return top and top.name or nil
end

return Nav
