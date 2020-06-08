## Name

lua-resty-protect - when cpu usage reaches the limit, request is randomly discarded

## Synopsis

```lua
lua_shared_dict protect_shm 128k;

http {
    init_by_lua_block {
        local params = {
            enable = "on",
            discard_percent = 10,
            protect_usage = 80,
        }
        local protect = require "protect"
        protect.init()
    }

    server {
        location / {
            access_by_lua_block {
                local protect = require "protect"
                protect.access()
            }
        }
    }
}
```
