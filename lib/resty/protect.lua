-- Copyright (C) 2020-2020 ZengJinji
-- refer: https://github.com/open-falcon/falcon-plus/blob/master/modules/agent/funcs/cpustat.go
-- refer: https://blog.csdn.net/zyjtx321/article/details/105973352/


local ngx = ngx
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_sleep = ngx.sleep
local ngx_exit = ngx.exit
local ngx_now = ngx.now
local ngx_header = ngx.header
local ngx_re_match = ngx.re.match
local ngx_timer_every = ngx.timer.every
local ngx_worker_id = ngx.worker.id
local ngx_worker_pid = ngx.worker.pid
local str_format = string.format
local math_random = math.random
local math_randomseed = math.randomseed
local io_open = io.open
local tonumber = tonumber
local tostring = tostring


local _M = { _VERSION = '0.1' }


local shm = ngx.shared["protect_shm"]
local enable = "on"
local discard_percent = 10
local protect_usage = 80
local discard_key = "discard"
local pattern = "^cpu[ ]+(\\d+)[ ]+(\\d+)[ ]+(\\d+)[ ]+(\\d+)[ ]+(\\d+)[ ]+(\\d+)[ ]+(\\d+)"
local g_cpu_usage = {{total = 0, idle = 0}, {total = 0, idle = 0}}
local protect_ctx = {
    up_count = 0,
    down_count = 0,
    discard = 0,
}


local function clear_cpu_stat()
    g_cpu_usage[1].total = 0
    g_cpu_usage[1].idle = 0

    g_cpu_usage[2].total = 0
    g_cpu_usage[2].idle = 0
end


local function flush_cpu_stat()
    local f = io_open("/proc/stat", "r")
    if not f then
        ngx_log(ngx_ERR, "open /proc/stat error");
        return false
    end
    
    local str = f:read()
    f:close()
    
    if not str then
        ngx_log(ngx_ERR, "read /proc/stat error");
        return false
    end

    local m = ngx_re_match(str, pattern, "ijo");
    if not m then
        ngx_log(ngx_ERR, str_format("/proc/stat style error, is %s ", str));
        return false
    end

    g_cpu_usage[1].total = g_cpu_usage[2].total
    g_cpu_usage[1].idle = g_cpu_usage[2].idle

    g_cpu_usage[2].total = 0
    for i = 1, 7 do
        g_cpu_usage[2].total = g_cpu_usage[2].total + tonumber(m[i])
    end

    g_cpu_usage[2].idle = tonumber(m[4])

    return true
end


local function cal_cpu_usage()
    local od, nd, id, sd, usage;

    if g_cpu_usage[1].total == 0
        or g_cpu_usage[2].total == 0
        or g_cpu_usage[1].total == g_cpu_usage[2].total
    then
        return 0;
    end

    od = g_cpu_usage[1].total
    nd = g_cpu_usage[2].total

    id = g_cpu_usage[2].idle
    sd = g_cpu_usage[1].idle

    usage = 100.0 - (id - sd)*1.0/(nd - od) * 100.00;

    return usage
end


local function set_discard(premature)
    if premature then
        return
    end

    if not flush_cpu_stat() then
        clear_cpu_stat()
        return
    end

    if enable ~= "on" then
        return
    end

    local usage = cal_cpu_usage()
    if usage == 0 then
        return
    end

    local discard = shm:get(shm, discard_key) or 0

    if usage <= protect_usage then
        protect_ctx.up_count = 0;

        if discard <= 0 then
            return
        end

        protect_ctx.down_count = protect_ctx.down_count + 1
        if protect_ctx.down_count >= 3 then
            protect_ctx.down_count = 0
            shm:set(discard_key, discard - discard_percent)
        end

    -- usage > protect_usage
    else
        protect_ctx.down_count = 0;
        if discard >= 100 then
            return
        end
        
        protect_ctx.up_count = protect_ctx.up_count + 1
        if protect_ctx.up_count >= 3 then
            protect_ctx.up_count = 0
            shm:set(discard_key, discard + discard_percent)
        end
    end
end


function _M.worker_init(params)
    if params.enable then
        enable = params.enable
    end

    if params.discard_percent then
        discard_percent = params.discard_percent
    end

    if params.protect_usage then
        protect_usage = params.protect_usage
    end

    local str = tostring(ngx_now()*1000):reverse():sub(1,9)
    local seed_value = tonumber(str) + ngx_worker_pid()
    math_randomseed(seed_value)

    -- only one worker calculate cpu usage and set discard
    if ngx_worker_id() ~= 0 then
        return
    end

    ngx_timer_every(1, set_discard)
end


function _M.protect()
    if enable ~= "on" then
        return
    end

    local discard = shm:get(discard_key) or 0
    if math_random(100) > discard then
        return
    end

    ngx_sleep(1)
    ngx_header["X-Lua-Protect"] = "true"
    ngx_exit(429)
end


return _M
