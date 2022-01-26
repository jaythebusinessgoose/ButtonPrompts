
-- The prompt type determines what icon is shown along with the prompt.
local PROMPT_TYPE <const> = {
	DOOR = 0,
	INTERACT = 1,
	VIEW = 2,
	SPEECH = 3,
}

local active = false
local sound_callback = nil
local station_callback = nil
local reset_callback = nil

local tvs = {}
local callbacks = {}
local shop_callbacks = {}
local button_prompts_hidden = false
local function reset_button_prompts()
	tvs = {}
	button_prompts_hidden = false
    for _, callback in pairs(callbacks) do
        clear_callback(callback)
    end
    for _, callback in pairs(shop_callbacks) do
        clear_callback(callback)
    end
    callbacks = {}
    shop_callbacks = {}
end

-- If hidden=true, hide all button prompts. If hidden=false, enable all button prompts such that
-- prompts near the player will be visible.
local function hide_button_prompts(hidden)
	button_prompts_hidden = hidden
end

-- Spawn a button prompt at the coordinates.
-- prompt_type: Sets the icon that will be used along with the prompt.
-- x, y, layer: Position of the prompt.
local function spawn_button_prompt(prompt_type, x, y, layer)
    -- Spawn a TV to "host" the prompt. We will hide the TV and silence its sound.
    local tv_uid = spawn_entity(ENT_TYPE.ITEM_TV, x, y, layer, 0, 0)
    local tv = get_entity(tv_uid)
    tv.flags = set_flag(tv.flags, ENT_FLAG.INVISIBLE)
    local prompt = get_entity(entity_get_items_by(tv.fx_button.uid, ENT_TYPE.FX_BUTTON_DIALOG, 0)[1])
    prompt.animation_frame = 137 + 16 * prompt_type
    tvs[#tvs+1] = tv
    return tv_uid
end

-- Spawn a button prompt attached to an entity.
-- prompt_type: Sets the icon that will be used along with the prompt.
-- on_entity_uid: Entity that the prompt will attach to.
local function spawn_button_prompt_on(prompt_type, on_entity_uid)
    local x, y, layer = get_position(on_entity_uid)
    local on_entity = get_entity(on_entity_uid)
    -- Spawn a TV to "host" the prompt. We will hide the TV and silence its sound.
    local tv_uid = spawn_entity(ENT_TYPE.ITEM_TV, x, y, layer, 0, 0)
    local tv = get_entity(tv_uid)
    tv.flags = set_flag(tv.flags, ENT_FLAG.INVISIBLE)
    tv.flags = set_flag(tv.flags, ENT_FLAG.NO_GRAVITY)
    local prompt = get_entity(entity_get_items_by(tv.fx_button.uid, ENT_TYPE.FX_BUTTON_DIALOG, 0)[1])
    prompt.animation_frame = 137 + 16 * prompt_type
    tvs[#tvs+1] = tv

    callbacks[tv_uid] = set_callback(function()
        local x, y, layer = get_position(on_entity_uid)
        local on_entity_now = get_entity(on_entity_uid)
        local tv_now = get_entity(tv_uid)
        if on_entity_now ~= on_entity or tv_now ~= tv then
            clear_callback(callbacks[tv_uid])
            callbacks[tv_uid] = nil
            tv:destroy()
            return
        end
        -- Do not try moving the TV into a floor tile, since that will destroy it.
        local tiles = get_entities_at(0, MASK.FLOOR | MASK.ACTIVEFLOOR, x, y, layer, .5)
        if #tiles == 0 then
            tv.x, tv.y, tv.layer = x, y, layer
        end
    end, ON.GAMEFRAME)
    return tv_uid
end

local function spawn_shop_prompt_on(prompt_type, on_entity_uid, item_name, value_text, show_price_icon)
    item_name = item_name or ""
    value_text = value_text or ""
    local tv_uid = spawn_button_prompt_on(prompt_type, on_entity_uid)
    local tv = get_entity(tv_uid)

    local width = 6
    local height = 3

    tv.fx_button.y = 2.3 --1
    tv.fx_button.x = -1 --1.3 - width / 2

    local function update_item_name(new_item_name)
        item_name = new_item_name
    end

    local function update_value_text(new_value_text)
        value_text = new_value_text
    end

    shop_callbacks[tv_uid] = set_callback(function(ctx, draw_depth)
        if draw_depth ~= 1 then return end
        if button_prompts_hidden then return end
        local black = Color:black()
        local white = Color:white()
        local gray = Color:gray()
        black.a = tv.fx_button.color.a
        white.a = tv.fx_button.color.a
        gray.a = tv.fx_button.color.a

        local x, y = get_position(on_entity_uid) --tv.x, tv.y
        y = y - 1.3
        local topy = y + 2
        local midx = x

        ctx:draw_world_texture(TEXTURE.DATA_TEXTURES_MENU_BASIC_3, 5, 0, x - 1.5, y + 3.5, x + 1.5, y + 2, white)

        local screenx1, screeny1 = screen_position(x, y + 3.1)
        local screenx2, screeny2 = screen_position(x, y + 2.62)
        local text = item_name
        local text2 = value_text
        ctx:draw_text(text, screenx1, screeny1, .00064, .00064, black, VANILLA_TEXT_ALIGNMENT.CENTER, VANILLA_FONT_STYLE.ITALIC)
        ctx:draw_text(text2, screenx2, screeny2, .0005, .0005, white, VANILLA_TEXT_ALIGNMENT.CENTER, VANILLA_FONT_STYLE.ITALIC)

    end, ON.RENDER_PRE_DRAW_DEPTH)
    return {
        tv_uid = tv_uid,
        tv = tv,
        update_item_name = update_item_name,
        update_value_text = update_value_text,
    }
end

local function activate()
    if active then return end
    active = true
    -- Silence the sound of TVs turning on -- these TVs are used to host the button prompts.
    sound_callback = set_vanilla_sound_callback(
        VANILLA_SOUND.ITEMS_TV_LOOP,
        VANILLA_SOUND_CALLBACK_TYPE.STARTED,
        function(playing_sound)
            playing_sound:set_volume(0)
        end)

    station_callback = set_callback(function()
        for _, tv in ipairs(tvs) do
            -- If the station was changed, reset it back to 0 (off).
            tv.station = 0
            if button_prompts_hidden then
                tv.flags = clr_flag(tv.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
            else
                tv.flags = set_flag(tv.flags, ENT_FLAG.ENABLE_BUTTON_PROMPT)
            end
        end
    end, ON.GAMEFRAME)

    reset_callback = set_callback(function()
        reset_button_prompts()
    end, ON.PRE_LOAD_LEVEL_FILES)
end

local function deactivate()
    if not active then return end
    active = false
    reset_button_prompts()
    if sound_callback then
        clear_vanilla_sound_callback(sound_callback)
    end
    if station_callback then
        clear_callback(station_callback)
    end
    if reset_callback then
        clear_callback(reset_callback)
    end
end

set_callback(function(ctx)
    -- Initialize in the active state.
    activate()
end, ON.LOAD)

return {
    PROMPT_TYPE = PROMPT_TYPE,
    spawn_button_prompt = spawn_button_prompt,
    spawn_button_prompt_on = spawn_button_prompt_on,
    spawn_shop_prompt_on = spawn_shop_prompt_on,
    hide_button_prompts = hide_button_prompts,
    activate = activate,
    deactivate = deactivate,
}
