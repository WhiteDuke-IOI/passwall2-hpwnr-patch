-- /usr/share/passwall2/hpwnr.lua
-- hpwnr integration module for PassWall2
-- This file is NOT part of the passwall2 package and survives updates.

local luci_sys = require "luci.sys"
local nixio_fs = require "nixio.fs"

local M = {}

-- ── Утилиты ─────────────────────────────────────────────────

local function shellquote(s)
    if not s then return "''" end
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

-- ── Определение типа URL ────────────────────────────────────

function M.is_hpwnr_url(url)
    if not url then return false end
    if url:match("^happ://") then return true end
    if url:match("^v2raytun://") then return true end
    if url:match("^https?://") and url:match("[?&]key=key%d") then return true end
    return false
end

local function is_encrypted(url)
    return url:match("^happ://") ~= nil or url:match("^v2raytun://") ~= nil
end

-- ── Шаг 1: Расшифровка ссылки ───────────────────────────────

local function decrypt_link(encrypted_url)
    local cmd = "hpwnr " .. shellquote(encrypted_url) .. " 2>/dev/null"
    local result = luci_sys.exec(cmd)
    if not result or result == "" then return nil end
    return trim(result):match("^(https?://[^\r\n]+)")
end

-- ── Шаг 2: Заголовки через curl ─────────────────────────────

local function curl_headers(real_url, ua, hwid)
    local tmp_hdr = "/tmp/hpwnr_hdr_" .. tostring(os.time())
    local cmd = "curl -sSL --max-time 20 --connect-timeout 10"
        .. " -D " .. shellquote(tmp_hdr)
        .. " -o /dev/null"
        .. " -w '%{http_code}'"
    if ua and ua ~= "" then
        cmd = cmd .. " -A " .. shellquote(ua)
    end
    if hwid and hwid ~= "" then
        cmd = cmd .. " -H " .. shellquote("X-HWID: " .. hwid)
    end
    cmd = cmd .. " " .. shellquote(real_url) .. " 2>/dev/null"

    local code_str = luci_sys.exec(cmd) or ""
    local http_code = tonumber(trim(code_str)) or 0

    local headers = ""
    if nixio_fs.access(tmp_hdr) then
        local fh = io.open(tmp_hdr, "r")
        if fh then
            headers = fh:read("*all") or ""
            fh:close()
        end
        luci_sys.call("rm -f " .. shellquote(tmp_hdr))
    end

    return http_code, headers
end

-- ── Шаг 3: Тело через hpwnr ────────────────────────────────

local function fetch_body(url, tmp_file, ua, hwid)
    -- b64: AES-дешифровка + base64-декод → чистый текст
    -- Если подписка возвращает данные НЕ в base64, замените b64 на raw
    local cmd = "hpwnr " .. shellquote(url)
    if hwid and hwid ~= "" then
        cmd = cmd .. " hwid " .. shellquote(hwid)
    end
    if ua and ua ~= "" then
        cmd = cmd .. " ua " .. shellquote(ua)
    end
    cmd = cmd .. " b64 > " .. shellquote(tmp_file) .. " 2>/dev/null"
    local rc = luci_sys.call(cmd)

    -- hpwnr при ответе > 15000 символов пишет в hpwnresp_<domain>.txt
    if rc == 0 and nixio_fs.access(tmp_file) then
        local f = io.open(tmp_file, "r")
        if f then
            local content = f:read("*all") or ""
            f:close()
            if trim(content) == "" then
                local domain = url:match("^%w+://([^/:]+)")
                if domain then
                    local hf = "/tmp/hpwnresp_" .. domain .. ".txt"
                    if nixio_fs.access(hf) then
                        luci_sys.call("mv " .. shellquote(hf)
                            .. " " .. shellquote(tmp_file))
                    end
                end
            end
        end
    end

    return rc
end

-- ── Извлечение заголовка (case-insensitive) ─────────────────

local function extract_header(headers, name)
    if not headers or headers == "" then return nil end
    local lower_name = name:lower()
    for line in headers:gmatch("[^\r\n]+") do
        local hname, hval = line:match("^([^:]+):%s*(.+)$")
        if hname and hname:lower() == lower_name then
            return trim(hval)
        end
    end
    return nil
end

-- ── Главная функция ─────────────────────────────────────────
-- Возвращает: ok, http_code, userinfo, logs

function M.process(url, ua, hwid, tmp_file)
    local logs = {}
    local real_url = url

    -- Шаг 1: расшифровка ссылки (happ:// / v2raytun://)
    if is_encrypted(url) then
        logs[#logs + 1] = "hpwnr: decrypting link..."
        real_url = decrypt_link(url)
        if not real_url then
            logs[#logs + 1] = "hpwnr: FAILED to decrypt link"
            return false, 0, nil, logs
        end
        logs[#logs + 1] = "hpwnr: resolved OK"
    end

    -- Шаг 2: заголовки
    local http_code, headers = curl_headers(real_url, ua, hwid)
    if http_code >= 400 then
        logs[#logs + 1] = string.format("hpwnr: server returned HTTP %d", http_code)
        return false, http_code, nil, logs
    end

    local userinfo = extract_header(headers, "subscription-userinfo")
    if userinfo then
        logs[#logs + 1] = "Subscription-Userinfo: " .. userinfo
    end

    -- Шаг 3: расшифрованное тело
    logs[#logs + 1] = "hpwnr: fetching body..."
    local rc = fetch_body(real_url, tmp_file, ua, hwid)
    if rc ~= 0 then
        logs[#logs + 1] = string.format("hpwnr: fetch FAILED (rc=%d)", rc)
        return false, http_code, userinfo, logs
    end

    logs[#logs + 1] = "hpwnr: OK"
    return true, http_code, userinfo, logs
end

return M