--- @type mq
local mq = require('mq')
--- @type ImGui
require 'ImGui'

local camp = require('aqo.routines.camp')
local common = require('aqo.common')
local config = require('aqo.configuration')
local mode = require('aqo.mode')
local state = require('aqo.state')

-- GUI Control variables
local open_gui = true
local should_draw_gui = true

local class_funcs
local ui = {}

ui.set_class_funcs = function(funcs)
    class_funcs = funcs
end

ui.toggle_gui = function(open)
    open_gui = open
end

local function help_marker(desc)
    ImGui.TextDisabled('(?)')
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(desc)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

ui.draw_combo_box = function(label, resultvar, options, bykey)
    ImGui.Text(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(150)
    if ImGui.BeginCombo('##'..label, resultvar) then
        for i,j in pairs(options) do
            if bykey then
                if ImGui.Selectable(i, i == resultvar) then
                    resultvar = i
                end
            else
                if ImGui.Selectable(j, j == resultvar) then
                    resultvar = j
                end
            end
        end
        ImGui.EndCombo()
    end
    return resultvar
end

ui.draw_check_box = function(labelText, idText, resultVar, helpText)
    if resultVar then
        ImGui.TextColored(0, 1, 0, 1, labelText)
    else
        ImGui.TextColored(1, 0, 0, 1, labelText)
    end
    ImGui.SameLine()
    help_marker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(150)
    resultVar,_ = ImGui.Checkbox(idText, resultVar)
    return resultVar
end

ui.draw_input_int = function(labelText, idText, resultVar, helpText)
    ImGui.Text(labelText)
    ImGui.SameLine()
    help_marker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(150)
    resultVar = ImGui.InputInt(idText, resultVar)
    return resultVar
end

ui.draw_input_text = function(labelText, idText, resultVar, helpText)
    ImGui.Text(labelText)
    ImGui.SameLine()
    help_marker(helpText)
    ImGui.SameLine()
    ImGui.SetCursorPosX(150)
    resultVar = ImGui.InputText(idText, resultVar)
    return resultVar
end

ui.get_next_item_loc = function()
    ImGui.SameLine()
    local x = ImGui.GetCursorPosX()
    if x < 205 then ImGui.SetCursorPosX(205) elseif x < 410 then ImGui.SetCursorPosX(410) end
    local avail = ImGui.GetContentRegionAvail()
    if x >= 410 or avail < 95 then
        ImGui.NewLine()
    end
end

local function draw_assist_tab()
    config.set_assist(ui.draw_combo_box('Assist', config.get_assist(), common.ASSISTS, true))
    config.set_auto_assist_at(ui.draw_input_int('Assist %', '##assistat', config.get_auto_assist_at(), 'Percent HP to assist at'))
    config.set_switch_with_ma(ui.draw_check_box('Switch With MA', '##switchwithma', config.get_switch_with_ma(), 'Switch targets with MA'))
end

local function draw_camp_tab()
    local current_camp_radius = config.get_camp_radius()
    config.set_camp_radius(ui.draw_input_int('Camp Radius', '##campradius', config.get_camp_radius(), 'Camp radius to assist within'))
    config.set_chase_target(ui.draw_input_text('Chase Target', '##chasetarget', config.get_chase_target(), 'Chase Target'))
    config.set_chase_distance(ui.draw_input_int('Chase Distance', '##chasedist', config.get_chase_distance(), 'Distance to follow chase target'))
    if current_camp_radius ~= config.get_camp_radius() then
        camp.set_camp()
    end
end

local function draw_pull_tab()
    local current_radius = config.get_pull_radius()
    local current_pullarc = config.get_pull_arc()
    config.set_pull_radius(ui.draw_input_int('Pull Radius', '##pullrad', config.get_pull_radius(), 'Radius to pull mobs within'))
    config.set_pull_z_low(ui.draw_input_int('Pull ZLow', '##pulllow', config.get_pull_z_low(), 'Z Low pull range'))
    config.set_pull_z_high(ui.draw_input_int('Pull ZHigh', '##pullhigh', config.get_pull_z_high(), 'Z High pull range'))
    config.set_pull_min_level(ui.draw_input_int('Pull Min Level', '##pullminlvl', config.get_pull_min_level(), 'Minimum level mobs to pull'))
    config.set_pull_max_level(ui.draw_input_int('Pull Max Level', '##pullmaxlvl', config.get_pull_max_level(), 'Maximum level mobs to pull'))
    config.set_pull_arc(ui.draw_input_int('Pull Arc', '##pullarc', config.get_pull_arc(), 'Only pull from this slice of the radius, centered around your current heading'))
    if current_radius ~= config.get_pull_radius() or current_pullarc ~= config.get_pull_arc() then
        camp.set_camp()
    end
end

local function draw_debug_tab()
    ImGui.TextColored(1, 1, 0, 1, 'Status:')
    ImGui.SameLine()
    local x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    if state.get_paused() then
        ImGui.TextColored(1, 0, 0, 1, 'PAUSED')
    else
        ImGui.TextColored(0, 1, 0, 1, 'RUNNING')
    end
    ImGui.TextColored(1, 1, 0, 1, 'Mode:')
    ImGui.SameLine()
    x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    ImGui.TextColored(1, 1, 1, 1, config.get_mode():get_name())

    ImGui.TextColored(1, 1, 0, 1, 'Camp:')
    ImGui.SameLine()
    x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    local camp = state.get_camp()
    if camp then
        ImGui.TextColored(1, 1, 0, 1, string.format('X: %.02f  Y: %.02f  Z: %.02f  Rad: %d', camp.X, camp.Y, camp.Z, config.get_camp_radius()))
    else
        ImGui.TextColored(1, 0, 0, 1, '--')
    end

    ImGui.TextColored(1, 1, 0, 1, 'Target:')
    ImGui.SameLine()
    x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    ImGui.TextColored(1, 0, 0, 1, string.format('%s', mq.TLO.Target()))

    ImGui.TextColored(1, 1, 0, 1, 'AM_I_DEAD:')
    ImGui.SameLine()
    x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    ImGui.TextColored(1, 0, 0, 1, string.format('%s', state.get_i_am_dead()))

    ImGui.TextColored(1, 1, 0, 1, 'Burning:')
    ImGui.SameLine()
    x,_ = ImGui.GetCursorPos()
    ImGui.SetCursorPosX(90)
    ImGui.TextColored(1, 0, 0, 1, string.format('%s', state.get_burn_active()))
end

local function draw_body()
    if ImGui.BeginTabBar('##tabbar') then
        if ImGui.BeginTabItem('Assist') then
            ImGui.PushItemWidth(159)
            draw_assist_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Camp') then
            ImGui.PushItemWidth(159)
            draw_camp_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Skills') then
            ImGui.PushItemWidth(159)
            class_funcs.draw_skills_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Burn') then
            ImGui.PushItemWidth(159)
            class_funcs.draw_burn_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Pull') then
            ImGui.PushItemWidth(159)
            draw_pull_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem('Debug') then
            ImGui.PushItemWidth(159)
            draw_debug_tab()
            ImGui.PopItemWidth()
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end
end

local function draw_control_buttons()
    if state.get_paused() then
        if ImGui.Button('RESUME') then
            camp.set_camp()
            state.set_paused(false)
        end
    else
        if ImGui.Button('PAUSE') then
            state.set_paused(true)
        end
    end
    ImGui.SameLine()
    if ImGui.Button('Save Settings') then
        class_funcs.save_settings()
    end
    ImGui.SameLine()
    if state.get_debug() then
        if ImGui.Button('Debug OFF') then
            state.set_debug(false)
        end
    else
        if ImGui.Button('Debug ON') then
            state.set_debug(true)
        end
    end

    local current_mode = config.get_mode():get_name()
    ImGui.PushItemWidth(160)
    config.set_mode(mode.from_string(ui.draw_combo_box('Mode', config.get_mode():get_name(), mode.mode_names)))
    ImGui.PopItemWidth()
    if current_mode ~= config.get_mode():get_name() then
        camp.set_camp()
    end
end

local function draw_header()
    ImGui.Text('Bot Status: ')
    ImGui.SameLine()
    if state.get_paused() then
        ImGui.TextColored(1, 0, 0, 1, 'PAUSED')
    else
        ImGui.TextColored(0, 1, 0, 1, 'RUNNING')
    end

    draw_control_buttons()
end

local function push_styles()
    ImGui.PushStyleColor(ImGuiCol.WindowBg, .1, .1, .1, .7)
    ImGui.PushStyleColor(ImGuiCol.TitleBg, 0, .3, .3, 1)
    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0, .5, .5, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0, .3, .3, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0, .4, .4, 1)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0, .4, .4, 1)
    ImGui.PushStyleColor(ImGuiCol.Button, 0,.3,.3,1)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0,.5,.5,1)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0,.5,.5,1)
    ImGui.PushStyleColor(ImGuiCol.PopupBg, 0,.5,.5,1)
    ImGui.PushStyleColor(ImGuiCol.Tab, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.TabActive, 0, .4, .4, 1)
    ImGui.PushStyleColor(ImGuiCol.TabHovered, 0, .5, .50, 1)
    ImGui.PushStyleColor(ImGuiCol.TabUnfocused, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.TabUnfocusedActive, 0, .3, .3, 1)
    ImGui.PushStyleColor(ImGuiCol.TextDisabled, 1, 1, 1, 1)
    ImGui.PushStyleColor(ImGuiCol.CheckMark, 1, 1, 1, 1)
    ImGui.PushStyleColor(ImGuiCol.Separator, 0, .4, .4, 1)
end

local function pop_styles()
    ImGui.PopStyleColor(18)
end

-- ImGui main function for rendering the UI window
ui.main = function()
    if not open_gui then return end
    push_styles()
    open_gui, should_draw_gui = ImGui.Begin('AQO Bot 1.0', open_gui, ImGuiWindowFlags.AlwaysAutoResize)
    if should_draw_gui then
        draw_header()
        draw_body()
    end
    ImGui.End()
    pop_styles()
end

return ui