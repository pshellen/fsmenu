local json = require "json"

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font("font.ttf")
local offline_logo = resource.load_image("offline-logo.png")
local white = resource.create_colored_texture(1, 1, 1, 1)
local surface = resource.create_colored_texture(1, 1, 1, 1)
local placeholder = resource.create_colored_texture(1, 1, 1, 1)
local saber_glow_wide = resource.create_colored_texture(0.03, 0.49, 0.82, 0.16)
local saber_glow = resource.create_colored_texture(0.12, 0.78, 1, 0.34)
local saber_core = resource.create_colored_texture(0.82, 0.97, 1, 0.92)
local config = { display_profile = "3840x1080", playback_mode = "static", page_duration_seconds = 25, combo_font_scale_percent = 100, alacarte_font_scale_percent = 100, debug = false }
local state = nil
local font_region = nil
local images = {}
local ad_media = {}
local ad_media_errors = {}
local last_ad_error = nil
local last_manifest_version = nil

local profiles = {
    ["3840x1080"] = {3840, 1080},
    ["2160x3840"] = {2160, 3840},
    ["1920x1080"] = {1920, 1080},
    ["3840x2160"] = {3840, 2160},
}

local function sorted_available(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        if value.available ~= false then out[#out + 1] = value end
    end
    table.sort(out, function(a, b)
        if (a.display_order or 0) == (b.display_order or 0) then return (a.name or "") < (b.name or "") end
        return (a.display_order or 0) < (b.display_order or 0)
    end)
    return out
end

local function money(value)
    if value.display_price and value.display_price ~= "" then return value.display_price end
    return string.format("$%.2f", tonumber(value.price) or 0)
end

local function load_media(manifest)
    images = {}
    ad_media = {}
    ad_media_errors = {}
    last_ad_error = nil
    local function load(path)
        if path and path ~= "" and not images[path] then
            local ok, result = pcall(resource.load_image, path)
            if ok then images[path] = result end
        end
    end
    for _, combo in ipairs(manifest.combos or {}) do load(combo.local_image) end
    for _, category in ipairs(manifest.categories or {}) do
        load(category.local_image)
        for _, item in ipairs(category.items or {}) do load(item.local_image) end
    end
    for _, ad in ipairs(manifest.advertisements or {}) do
        local path = ad.local_media
        if path and path ~= "" then
            if ad.media_type == "video" then
                local ok, result = pcall(resource.load_video, {file=path, audio=false, looped=true, paused=false})
                if ok then ad_media[path] = {resource=result, media_type="video"} end
            else
                local ok, result = pcall(resource.load_image, path)
                if ok then ad_media[path] = {resource=result, media_type="image"} end
            end
        end
    end
end

util.json_watch("config.json", function(value)
    config = value or config
end)

util.json_watch("state.json", function(value)
    state = value
    if state and state.manifest and state.manifest.manifest_version ~= last_manifest_version then
        last_manifest_version = state.manifest.manifest_version
        load_media(state.manifest)
    end
end)

local function scaled_font_size(size)
    local legacy = tonumber(config.font_scale_percent) or 100
    local configured = legacy
    if font_region == "combo" then
        configured = tonumber(config.combo_font_scale_percent) or legacy
    elseif font_region == "alacarte" then
        configured = tonumber(config.alacarte_font_scale_percent) or legacy
    end
    local percent = math.max(75, math.min(125, configured))
    return size * percent / 100
end

local function text(x, y, value, size, r, g, b, a)
    font:write(x, y, tostring(value or ""), scaled_font_size(size), r or 0.05, g or 0.08, b or 0.13, a or 1)
end

local function centered(x1, x2, y, value, size, color)
    local width = font:width(tostring(value or ""), scaled_font_size(size))
    text(x1 + math.max(0, (x2 - x1 - width) / 2), y, value, size, unpack(color or {0.05, 0.08, 0.13, 1}))
end

local function wrapped_centered(x1, x2, y, value, size, line_height, max_lines, color)
    local words, lines, current = {}, {}, ""
    for word in tostring(value or ""):gmatch("%S+") do words[#words + 1] = word end
    local max_width = x2 - x1
    for _, word in ipairs(words) do
        local candidate = current == "" and word or current .. " " .. word
        if current ~= "" and font:width(candidate, scaled_font_size(size)) > max_width then
            lines[#lines + 1] = current
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = "" end
    while #lines > max_lines do
        lines[max_lines] = lines[max_lines] .. " " .. lines[max_lines + 1]
        table.remove(lines, max_lines + 1)
    end
    for index, line in ipairs(lines) do
        centered(x1, x2, y + (index - 1) * line_height, line, size, color)
    end
end

local function fit_image(path, x1, y1, x2, y2)
    local image = images[path]
    if not image then
        placeholder:draw(x1 + 8, y1 + 8, x2 - 8, y2 - 8)
        return
    end
    local status, iw, ih = image:state()
    if status ~= "loaded" or not iw or iw == 0 or not ih or ih == 0 then
        placeholder:draw(x1 + 8, y1 + 8, x2 - 8, y2 - 8)
        return
    end
    local scale = math.min((x2-x1)/iw, (y2-y1)/ih)
    local w, h = iw*scale, ih*scale
    image:draw(x1+(x2-x1-w)/2, y1+(y2-y1-h)/2, x1+(x2-x1+w)/2, y1+(y2-y1+h)/2)
end

local function render_offline_indicator(w, h)
    local status, iw, ih = offline_logo:state()
    if status ~= "loaded" or not iw or not ih or iw == 0 or ih == 0 then return end
    local indicator_h = math.min(w, h) * .055
    local indicator_w = indicator_h * iw / ih
    local margin = math.min(w, h) * .012
    offline_logo:draw(w-margin-indicator_w, h-margin-indicator_h, w-margin, h-margin, .88)
end

local function render_advertisement(manifest, w, h)
    local ads = {}
    for _, ad in ipairs(manifest.advertisements or {}) do
        local holder = ad_media[ad.local_media]
        if holder then
            local ok, status, detail = pcall(function() return holder.resource:state() end)
            if ok and (status == "loaded" or status == "paused" or status == "finished") then
                ads[#ads + 1] = ad
            elseif ok and status == "error" then
                last_ad_error = tostring(detail or "unknown decoder error")
                if not ad_media_errors[ad.local_media] then
                    ad_media_errors[ad.local_media] = true
                    print("advertisement media error " .. tostring(ad.local_media) .. ": " .. last_ad_error)
                end
            end
        end
    end
    if #ads == 0 then return false end
    local total = 0
    for _, ad in ipairs(ads) do total = total + math.max(1, tonumber(ad.duration_seconds) or 10) end
    local cursor = sys.now() % total
    local selected = ads[1]
    for _, ad in ipairs(ads) do
        cursor = cursor - math.max(1, tonumber(ad.duration_seconds) or 10)
        if cursor < 0 then selected = ad; break end
    end
    local holder = selected and ad_media[selected.local_media]
    if not holder then return false end
    holder.resource:draw(0, 0, w, h)
    return true
end

local function render_combo(manifest, w, h, with_ads)
    font_region = "combo"
    local combos = sorted_available(manifest.combos)
    local margin, gap = w * 0.018, w * 0.008
    local grid_top
    local has_ad = with_ads and render_advertisement(manifest, w, h * 0.5)
    if has_ad then
        grid_top = h * 0.5 + margin
    else
        local top = h * 0.035
        centered(0, w, top, "COMBOS", math.min(w, h) * 0.052, {0.03, 0.16, 0.34, 1})
        grid_top = top + math.min(w,h)*0.08
    end
    local columns = (#combos <= 5 and w > h * 0.8) and #combos or math.min(2, #combos)
    columns = math.max(1, columns)
    local rows = math.ceil(#combos / columns)
    local card_w = (w - margin*2 - gap*(columns-1))/columns
    local footer = math.min(w,h) * .025
    local card_h = (h - grid_top - margin - footer - gap*(rows-1))/rows
    for i, combo in ipairs(combos) do
        local col, row = (i-1)%columns, math.floor((i-1)/columns)
        local x1, y1 = margin+col*(card_w+gap), grid_top+row*(card_h+gap)
        local x2, y2 = x1+card_w, y1+card_h
        white:draw(x1, y1, x2, y2)
        local info_h = math.max(card_h*0.34, math.min(w,h)*0.17)
        fit_image(combo.local_image, x1, y1, x2, y2-info_h)
        local title_size = math.min(card_w*0.065, info_h*0.18)
        centered(x1, x2, y2-info_h+info_h*0.08, combo.name, title_size)
        wrapped_centered(x1+card_w*.04, x2-card_w*.04, y2-info_h+info_h*.34, combo.description or "", title_size*.55, title_size*.72, 2)
        centered(x1, x2, y2-info_h+info_h*.70, money(combo), title_size*.92, {0.03, 0.22, 0.52, 1})
    end
    centered(0, w, h-footer*.85, manifest.screen.tax_disclaimer or "", math.min(w,h)*.014, {0.2,0.25,0.3,1})
    return has_ad
end

local function render_categories(manifest, w, h)
    font_region = "alacarte"
    local source = sorted_available(manifest.categories)
    local categories, drinks = {}, {}
    for _, category in ipairs(source) do
        local name = string.lower(category.name or "")
        if name == "bottled water" or name == "fountain drinks" or name == "icee" then
            drinks[#drinks + 1] = category
        else
            categories[#categories + 1] = category
        end
    end
    if #drinks > 0 then categories[#categories + 1] = {name="Refreshing Drinks", groups=drinks} end
    local margin, gap = w*.025, w*.012
    local columns = (w/h > 1.25) and math.min(3, #categories) or math.min(2, #categories)
    columns = math.max(1, columns)
    local rows = math.ceil(#categories/columns)
    local cw = (w-margin*2-gap*(columns-1))/columns
    local ch = (h-margin*2-gap*(rows-1))/rows
    for i, category in ipairs(categories) do
        local col, row = (i-1)%columns, math.floor((i-1)/columns)
        local x, y = margin+col*(cw+gap), margin+row*(ch+gap)
        white:draw(x, y, x+cw, y+ch)
        local heading = math.min(cw*.085, ch*.10)
        text(x+cw*.05, y+ch*.05, category.name, heading, 0.02, 0.16, 0.34, 1)
        local hero_path = category.local_image
        if not hero_path then
            for _, item in ipairs(category.items or {}) do
                if item.local_image then hero_path = item.local_image; break end
            end
        end
        local category_name = string.lower(category.name or "")
        local has_hero = hero_path and (category_name == "popcorn" or category_name == "snacks")
        if has_hero then fit_image(hero_path, x+cw*.06, y+ch*.14, x+cw*.94, y+ch*.50) end
        local groups = category.groups or {category}
        local entries = 0
        for _, group in ipairs(groups) do entries = entries + #(sorted_available(group.items)) + (category.groups and 1 or 0) end
        local available_fraction = has_hero and .40 or .76
        local line = math.min(ch*.095, (ch*available_fraction)/math.max(1,entries))
        local cursor = 0
        for _, group in ipairs(groups) do
            if category.groups then
                local gy = y+(has_hero and ch*.53 or ch*.20)+cursor*line
                text(x+cw*.06, gy, string.upper(group.name or ""), line*.40, 0.07, 0.39, 0.54, 1)
                cursor = cursor + 1
            end
            for _, item in ipairs(sorted_available(group.items)) do
                local iy = y+(has_hero and ch*.53 or ch*.20)+cursor*line
                local price = money(item)
                local item_size = line*.43
                local measured_size = scaled_font_size(item_size)
                local total_width = font:width(item.name or "", measured_size) + font:width(price, measured_size) + cw*.06
                if total_width > cw*.88 then item_size = item_size * (cw*.88/total_width) end
                text(x+cw*.06, iy, item.name, item_size)
                text(x+cw*.94-font:width(price,scaled_font_size(item_size)), iy, price, item_size)
                cursor = cursor + 1
            end
        end
    end
end

local function render_saber_edges(w, h, center, y1)
    y1 = y1 or 0
    local points = {0, w}
    if center then points[#points + 1] = w * 0.5 end
    for _, x in ipairs(points) do
        saber_glow_wide:draw(math.max(0, x-28), y1, math.min(w, x+28), h)
        saber_glow:draw(math.max(0, x-12), y1, math.min(w, x+12), h)
        saber_core:draw(math.max(0, x-2), y1, math.min(w, x+2), h)
    end
end

local function render_full(manifest, w, h)
    local left = w*.50
    gl.pushMatrix()
    gl.translate(0, 0)
    render_combo(manifest, left, h, true)
    gl.popMatrix()
    gl.pushMatrix()
    gl.translate(left, 0)
    render_categories(manifest, w-left, h)
    gl.popMatrix()
    render_saber_edges(w, h, true)
end

function node.render()
    gl.clear(1, 1, 1, 1)
    local profile = profiles[config.display_profile] or profiles["3840x1080"]
    local w, h = profile[1], profile[2]
    local scale = math.min(NATIVE_WIDTH/w, NATIVE_HEIGHT/h)
    gl.pushMatrix()
    gl.translate((NATIVE_WIDTH-w*scale)/2, (NATIVE_HEIGHT-h*scale)/2)
    gl.scale(scale, scale)
    surface:draw(0, 0, w, h)
    if not state or not state.manifest then
        centered(0, w, h*.45, "Waiting for menu data…", math.min(w,h)*.05)
        if config.debug and state and state.error then
            centered(w*.08, w*.92, h*.54, tostring(state.error), math.min(w,h)*.018, {0.72,0.08,0.08,1})
        end
    else
        local manifest = state.manifest
        local layout = manifest.screen and manifest.screen.layout or config.screen_id
        if config.playback_mode == "alternate" then
            local duration = math.max(5, tonumber(config.page_duration_seconds) or 25)
            layout = math.floor(sys.now()/duration)%2 == 0 and "combo" or "alacarte"
        end
        if layout == "combo" then
            local has_ad = render_combo(manifest,w,h,true)
            render_saber_edges(w,h,false,has_ad and h*.5 or 0)
        elseif layout == "alacarte" then render_categories(manifest,w,h); render_saber_edges(w,h,false)
        else render_full(manifest,w,h) end
        font_region = nil
        if config.debug then
            text(w*.01,h*.01,(state.ok and "LIVE" or "STALE").."  "..tostring(manifest.manifest_version or ""),math.min(w,h)*.012,state.ok and 0 or 0.8,state.ok and 0.45 or 0.1,0.1,1)
            if last_ad_error then
                text(w*.01,h*.035,"AD VIDEO: "..last_ad_error,math.min(w,h)*.010,0.75,0.08,0.08,1)
            end
        end
        if state.ok == false then render_offline_indicator(w, h) end
    end
    gl.popMatrix()
end
