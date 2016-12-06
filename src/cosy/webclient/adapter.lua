local Mt       = {}
local Adapter  = setmetatable ({}, Mt)

function _G.print (...)
  Adapter.window.console:log (...)
end

package.preload ["lpeg"] = function ()
  return require "lulpeg"
end

package.preload ["cjson"] = function ()
  return require "dkjson"
end
local Json = require "cjson"

local Coromake = require "coroutine.make"

package.preload ["copas"] = function ()
  local copas    = {
    co        = nil,
    running   = nil,
    waiting   = {},
    ready     = {},
    timeout   = {},
    coroutine = Coromake (),
  }
  function copas.addthread (f, ...)
    local co = copas.coroutine.create (f)
    copas.ready [co] = {
      parameters = { ... },
    }
    if copas.co and coroutine.status (copas.co) == "suspended" then
      coroutine.resume (copas.co)
    end
    return co
  end
  function copas.sleep (time)
    time = time or -math.huge
    local co = copas.running
    if time > 0 then
      copas.timeout [co] = Adapter.window:setTimeout (function ()
        Adapter.window:clearTimeout (copas.timeout [co])
        copas.wakeup (co)
      end, time * 1000)
    end
    if time ~= 0 then
      copas.waiting [co] = true
      copas.ready   [co] = nil
      copas.coroutine.yield ()
    end
  end
  function copas.wakeup (co)
    Adapter.window:clearTimeout (copas.timeout [co])
    copas.timeout [co] = nil
    copas.waiting [co] = nil
    copas.ready   [co] = true
    if copas.co and coroutine.status (copas.co) == "suspended" then
      coroutine.resume (copas.co)
    end
  end
  function copas.loop ()
    copas.co = coroutine.running ()
    while true do
      for to_run, t in pairs (copas.ready) do
        if copas.coroutine.status (to_run) == "suspended" then
          copas.running = to_run
          local ok, err = copas.coroutine.resume (to_run, type (t) == "table" and table.unpack (t.parameters))
          copas.running = nil
          if not ok then
            Adapter.window.console:log (err)
          end
        end
      end
      for co in pairs (copas.ready) do
        if copas.coroutine.status (co) == "dead" then
          copas.waiting [co] = nil
          copas.ready   [co] = nil
        end
      end
      if  not next (copas.ready  )
      and not next (copas.waiting) then
        copas.co = nil
        return
      elseif not next (copas.ready) then
        coroutine.yield ()
      end
    end
  end
  return copas
end
local Copas = require "copas"

package.preload ["websocket"] = function ()
end

package.preload ["cosy.webclient.http"] = function ()
  local Http  = {}
  function Http.json (options)
    assert (type (options) == "table")
    local running = {
      copas = Copas.running,
      co    = coroutine.running (),
    }
    local response, json, err
    options.body    = options.body and Json.encode (options.body)
    options.headers = options.headers or {}
    options.headers ["Content-type"] = options.body and "application/json"
    options.headers ["Accept"      ] = "application/json"
    local r1 = Adapter.window:fetch (options.url, Adapter.tojs {
      method  = options.method or "GET",
      headers = options.headers,
    })
    local r2 = r1 ["then"] (r1, function (_, r)
      assert (r.status >= 200 and r.status < 400)
      response = r
      return response:text ()
    end)
    local r3 = r2 ["then"] (r2, function (_, text)
      json = Json.decode (text)
      if running.copas then
        Copas.wakeup (running.copas)
      else
        coroutine.resume (running.co)
      end
    end)
    r2:catch (function (_, e)
      err = e
      if running.copas then
        Copas.wakeup (running.copas)
      else
        coroutine.resume (running.co)
      end
    end)
    r3:catch (function (_, e)
      err = e
      if running.copas then
        Copas.wakeup (running.copas)
      else
        coroutine.resume (running.co)
      end
    end)
    if running.copas then
      Copas.sleep (-math.huge)
    else
      coroutine.yield ()
    end
    if json then
      return json, response.status, response.headers
    else
      return nil, err
    end
  end
  return Http
end
package.preload ["cosy.client.http"] = function ()
  return require "cosy.webclient.http"
end

Adapter.js        = _G.js
Adapter.window    = _G.js.global
Adapter.document  = _G.js.global.document
Adapter.navigator = _G.js.global.navigator
Adapter.locale    = _G.js.global.navigator.language
Adapter.origin    = _G.js.global.location.origin

function Adapter.tojs (t)
  if type (t) ~= "table" then
    return t
  elseif #t ~= 0 then
    local result = Adapter.js.new (Adapter.window.Array)
    for i = 1, #t do
      result [result.length] = Adapter.tojs (t [i])
    end
    return result
  else
    local result = Adapter.js.new (Adapter.window.Object)
    for k, v in pairs (t) do
      assert (type (k) == "string")
      result [k] = Adapter.tojs (v)
    end
    return result
  end
end

return Adapter