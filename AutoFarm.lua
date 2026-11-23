--// AUTO FARM PRO - DEPTH INCREMENTAL UI UPDATE
--// LocalScript / executor-compatible client script
--// Flight movement loop retained from the original uploaded script.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- SETTINGS
local farmSpeed = 40
local flightSpeed = 150
local walkSpeed = 32
local MIN_SPEED, MAX_SPEED, SPEED_STEP = 10, 200, 5
local MAX_FLIGHT_SPEED = 250

local waypoints = {}
local running, flying, noclip = false, false, false
local infiniteJump, autoFarm = false, false
local movementMode = "Teleport" -- "Teleport" or "Walk"
local destroyed = false

local character, humanoid, rootPart
local currentTween, flightVelocity, flightGyro, flightConnection, noclipConnection
local autoFlightTarget
local originalCollision = {}
local connections = {}
local historyRefresh

local function updateCharacter()
    character = player.Character
    if not character then return end
    humanoid = character:FindFirstChildOfClass("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
end

updateCharacter()
player.CharacterAdded:Connect(function()
    task.wait(0.8)
    updateCharacter()
    if humanoid then humanoid.WalkSpeed = walkSpeed end
end)

local function track(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoFarmPro"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = playerGui

local function round(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
end

local function outline(obj, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(70, 90, 130)
    s.Thickness = thickness or 1
    s.Parent = obj
end

local function label(parent, text, size, pos, fontSize)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Size, x.Position = size, pos
    x.Text = text
    x.TextColor3 = Color3.fromRGB(235, 240, 255)
    x.Font = Enum.Font.GothamBold
    x.TextSize = fontSize or 12
    x.TextWrapped = true
    x.Parent = parent
    return x
end

local function button(parent, text, height, color)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, height or 34)
    b.BackgroundColor3 = color or Color3.fromRGB(43, 54, 77)
    b.Text = text
    b.TextColor3 = Color3.fromRGB(245, 248, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 13
    b.AutoButtonColor = true
    b.Parent = parent
    round(b, 8)
    return b
end

local toast = label(gui, "", UDim2.fromOffset(280, 36), UDim2.new(0.5, -140, 0.9, 0), 12)
toast.BackgroundColor3 = Color3.fromRGB(25, 38, 55)
toast.BackgroundTransparency = 0.05
toast.Visible = false
toast.ZIndex = 30
round(toast, 8)
local toastToken = 0
local function notify(msg)
    toastToken += 1
    local token = toastToken
    toast.Text = msg
    toast.Visible = true
    task.delay(2.5, function()
        if toastToken == token and toast.Parent then toast.Visible = false end
    end)
end

-- MAIN PANEL: LEFT NAVIGATION + RIGHT DETAILS (Plak-inspired)
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0.72, 0, 0.70, 0)
main.Position = UDim2.new(0.14, 0, 0.15, 0)
main.BackgroundColor3 = Color3.fromRGB(19, 21, 26)
main.BorderSizePixel = 0
main.Parent = gui
round(main, 10)
outline(main, Color3.fromRGB(55, 60, 72), 1.2)

local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 42)
header.BackgroundColor3 = Color3.fromRGB(25, 28, 34)
header.BorderSizePixel = 0
header.Parent = main
round(header, 10)
label(header, "PLAK  /  DEPTH INCREMENTAL", UDim2.new(1, -100, 1, 0), UDim2.fromOffset(14, 0), 14).TextXAlignment = Enum.TextXAlignment.Left

local lockButton = Instance.new("TextButton")
lockButton.Size = UDim2.fromOffset(32, 28)
lockButton.Position = UDim2.new(1, -68, 0, 7)
lockButton.Text = "🔓"
lockButton.TextSize = 14
lockButton.BackgroundColor3 = Color3.fromRGB(42, 46, 55)
lockButton.TextColor3 = Color3.new(1,1,1)
lockButton.Parent = header
round(lockButton, 6)

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(30, 28)
closeButton.Position = UDim2.new(1, -34, 0, 7)
closeButton.Text = "×"
closeButton.TextSize = 20
closeButton.BackgroundColor3 = Color3.fromRGB(110, 43, 48)
closeButton.TextColor3 = Color3.new(1,1,1)
closeButton.Parent = header
round(closeButton, 6)

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 118, 1, -49)
sidebar.Position = UDim2.fromOffset(0, 46)
sidebar.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
sidebar.BorderSizePixel = 0
sidebar.Parent = main

local sideTitle = label(sidebar, "GENERAL", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(10, 8), 10)
sideTitle.TextColor3 = Color3.fromRGB(125, 132, 146)
sideTitle.TextXAlignment = Enum.TextXAlignment.Left

local navScroll = Instance.new("ScrollingFrame")
navScroll.Size = UDim2.new(1, -8, 1, -38)
navScroll.Position = UDim2.fromOffset(4, 34)
navScroll.BackgroundTransparency = 1
navScroll.BorderSizePixel = 0
navScroll.ScrollBarThickness = 2
navScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
navScroll.CanvasSize = UDim2.new()
navScroll.Parent = sidebar

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 5)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navScroll

local content = Instance.new("Frame")
content.Name = "Details"
content.Size = UDim2.new(1, -126, 1, -50)
content.Position = UDim2.fromOffset(124, 48)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.Parent = main

local pageTitle = label(content, "Main", UDim2.new(1, -12, 0, 28), UDim2.fromOffset(8, 0), 17)
pageTitle.TextXAlignment = Enum.TextXAlignment.Left
local pageSubtitle = label(content, "Select a category from the sidebar", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(8, 27), 10)
pageSubtitle.TextColor3 = Color3.fromRGB(125, 132, 146)
pageSubtitle.TextXAlignment = Enum.TextXAlignment.Left

local pageScroll = Instance.new("ScrollingFrame")
pageScroll.Size = UDim2.new(1, -8, 1, -58)
pageScroll.Position = UDim2.fromOffset(4, 52)
pageScroll.BackgroundTransparency = 1
pageScroll.BorderSizePixel = 0
pageScroll.ScrollBarThickness = 3
pageScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
pageScroll.CanvasSize = UDim2.new()
pageScroll.Parent = content

local pagesLayout = Instance.new("UIListLayout")
pagesLayout.Padding = UDim.new(0, 8)
pagesLayout.SortOrder = Enum.SortOrder.LayoutOrder
pagesLayout.Parent = pageScroll

local pageNames = {}
local selectedPage
local function makeSection(titleText)
    local page = Instance.new("Frame")
    page.Name = titleText:gsub("[^%w]", "") .. "Page"
    page.Size = UDim2.new(1, -6, 0, 0)
    page.AutomaticSize = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = pageScroll

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 2)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 2)
    padding.PaddingRight = UDim.new(0, 5)
    padding.Parent = page

    local nav = Instance.new("TextButton")
    nav.Size = UDim2.new(1, -4, 0, 36)
    nav.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
    nav.Text = "   " .. titleText
    nav.TextColor3 = Color3.fromRGB(175, 181, 193)
    nav.Font = Enum.Font.GothamMedium
    nav.TextSize = 11
    nav.TextXAlignment = Enum.TextXAlignment.Left
    local navOrder = {
        ["Auto Farm"] = 1, ["Fly"] = 2, ["Lightning"] = 3,
        ["Waypoints"] = 4, ["Movement"] = 5, ["Player"] = 6
    }
    nav.LayoutOrder = navOrder[titleText] or 99
    nav.Parent = navScroll
    round(nav, 6)

    local function select()
        for _, item in ipairs(pageNames) do
            item.page.Visible = false
            item.nav.BackgroundColor3 = Color3.fromRGB(31, 34, 41)
            item.nav.TextColor3 = Color3.fromRGB(175, 181, 193)
        end
        page.Visible = true
        nav.BackgroundColor3 = Color3.fromRGB(48, 55, 68)
        nav.TextColor3 = Color3.fromRGB(245, 247, 252)
        pageTitle.Text = titleText
        pageSubtitle.Text = "Configure " .. titleText
        selectedPage = page
    end

    nav.MouseButton1Click:Connect(select)
    table.insert(pageNames, {page = page, nav = nav, select = select})
    if #pageNames == 1 then select() end
    return page
end

local function addButton(parent, text, callback, color)
    local b = button(parent, text, 35, color)
    b.MouseButton1Click:Connect(callback)
    return b
end

local function addSlider(parent, titleText, minimum, maximum, initialValue, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 54)
    holder.BackgroundColor3 = Color3.fromRGB(30, 34, 43)
    holder.BorderSizePixel = 0
    holder.Parent = parent
    round(holder, 7)

    local title = label(holder, titleText, UDim2.new(0.72, 0, 0, 20), UDim2.fromOffset(9, 3), 11)
    title.TextXAlignment = Enum.TextXAlignment.Left
    local valueLabel = label(holder, tostring(initialValue), UDim2.new(0.25, -8, 0, 20), UDim2.new(0.75, 0, 0, 3), 11)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 8)
    bar.Position = UDim2.fromOffset(10, 34)
    bar.BackgroundColor3 = Color3.fromRGB(55, 62, 76)
    bar.BorderSizePixel = 0
    bar.Parent = holder
    round(bar, 5)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((initialValue - minimum) / (maximum - minimum), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(75, 145, 235)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    round(fill, 5)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new((initialValue - minimum) / (maximum - minimum), 0, 0.5, 0)
    knob.BackgroundColor3 = Color3.fromRGB(240, 244, 255)
    knob.BorderSizePixel = 0
    knob.Parent = bar
    round(knob, 8)
    outline(knob, Color3.fromRGB(75, 145, 235), 1)

    local draggingSlider = false
    local function setFromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local value = math.floor(minimum + (maximum - minimum) * alpha + 0.5)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(value)
        callback(value)
    end

    track(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            setFromX(input.Position.X)
        end
    end)
    track(knob.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            setFromX(input.Position.X)
        end
    end)
    track(UserInputService.InputChanged, function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    track(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    return holder
end

-- SIDE HISTORY PANEL (separate from main menu)
local history = Instance.new("Frame")
history.Name = "LocationHistory"
history.Size = UDim2.fromOffset(205, 250)
history.Position = UDim2.new(0.5, -365, 0.28, 0)
history.BackgroundColor3 = Color3.fromRGB(18, 24, 37)
history.BorderSizePixel = 0
history.Visible = false
history.Parent = gui
round(history, 10)
outline(history)

local historyHeader = Instance.new("TextButton")
historyHeader.Size = UDim2.new(1, -12, 0, 30)
historyHeader.Position = UDim2.fromOffset(6, 4)
historyHeader.BackgroundColor3 = Color3.fromRGB(27, 37, 55)
historyHeader.Text = "SAVED LOCATIONS  •  DRAG"
historyHeader.TextColor3 = Color3.fromRGB(235, 240, 255)
historyHeader.Font = Enum.Font.GothamBold
historyHeader.TextSize = 11
historyHeader.Parent = history
round(historyHeader, 7)
local historyScroll = Instance.new("ScrollingFrame")
historyScroll.Size = UDim2.new(1, -12, 1, -46)
historyScroll.Position = UDim2.fromOffset(6, 40)
historyScroll.BackgroundTransparency = 1
historyScroll.BorderSizePixel = 0
historyScroll.ScrollBarThickness = 4
historyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
historyScroll.Parent = history
local historyLayout = Instance.new("UIListLayout")
historyLayout.Padding = UDim.new(0, 4)
historyLayout.Parent = historyScroll

local function refreshHistory()
    for _, child in ipairs(historyScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
    end
    if #waypoints == 0 then
        local empty = label(historyScroll, "No saved locations yet", UDim2.new(1, -4, 0, 32), UDim2.new(), 11)
        empty.TextColor3 = Color3.fromRGB(170, 180, 200)
        return
    end
    for i, pos in ipairs(waypoints) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 48)
        row.BackgroundColor3 = Color3.fromRGB(35, 45, 64)
        row.BorderSizePixel = 0
        row.Parent = historyScroll
        round(row, 6)
        local info = label(row,
            string.format("#%d  X %.1f | Y %.1f | Z %.1f", i, pos.X, pos.Y, pos.Z),
            UDim2.new(1, -42, 1, 0), UDim2.fromOffset(6, 0), 9)
        info.TextXAlignment = Enum.TextXAlignment.Left
        local del = Instance.new("TextButton")
        del.Size = UDim2.fromOffset(30, 30)
        del.Position = UDim2.new(1, -34, 0.5, -15)
        del.Text = "×"
        del.TextColor3 = Color3.new(1,1,1)
        del.BackgroundColor3 = Color3.fromRGB(130, 43, 49)
        del.Parent = row
        round(del, 6)
        del.MouseButton1Click:Connect(function()
            table.remove(waypoints, i)
            refreshHistory()
            notify("Location removed")
        end)
    end
end
historyRefresh = refreshHistory

-- WAYPOINTS + MODE
local waypointSection = makeSection("Waypoints")
addButton(waypointSection, "+ SAVE CURRENT LOCATION", function()
    updateCharacter()
    if not rootPart then notify("Character not found") return end
    table.insert(waypoints, rootPart.Position)
    refreshHistory()
    notify("Saved location #" .. #waypoints)
end, Color3.fromRGB(42, 100, 76))

local historyToggle
historyToggle = addButton(waypointSection, "OPEN / CLOSE LOCATION HISTORY", function()
    history.Visible = not history.Visible
    if history.Visible then refreshHistory() end
end)

local teleportModeButton, walkModeButton
local function setMovementMode(mode)
    movementMode = mode
    teleportModeButton.BackgroundColor3 = mode == "Teleport" and Color3.fromRGB(38, 115, 75) or Color3.fromRGB(43, 54, 77)
    walkModeButton.BackgroundColor3 = mode == "Walk" and Color3.fromRGB(38, 115, 75) or Color3.fromRGB(43, 54, 77)
    notify("Movement mode: " .. mode)
end
teleportModeButton = addButton(waypointSection, "TELEPORT (INSTANT)", function() setMovementMode("Teleport") end)
walkModeButton = addButton(waypointSection, "WALK TO TARGET", function() setMovementMode("Walk") end)
teleportModeButton.BackgroundColor3 = Color3.fromRGB(38, 115, 75)

local function stopFarm()
    running = false
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end
end

local function moveToPosition(position, speed)
    updateCharacter()
    if not rootPart or not humanoid then return false end
    if movementMode == "Teleport" then
        rootPart.CFrame = CFrame.new(position)
        return true
    end

    local distance = (rootPart.Position - position).Magnitude
    humanoid.WalkSpeed = speed or walkSpeed
    humanoid:MoveTo(position)
    local started = os.clock()
    while running and os.clock() - started < math.max(distance / math.max(walkSpeed, 1) + 3, 5) do
        if not rootPart or (rootPart.Position - position).Magnitude < 4 then return true end
        task.wait(0.12)
    end
    return rootPart and (rootPart.Position - position).Magnitude < 6
end

local startWaypointFarm
local startButton = addButton(waypointSection, "START WAYPOINT FARM", function()
    if running then notify("Already running") return end
    updateCharacter()
    if not rootPart or #waypoints == 0 then notify("Save at least one location first") return end
    if flying then notify("Turn off flight before farming") return end
    running = true
    task.spawn(function()
        while running and not destroyed do
            for _, pos in ipairs(waypoints) do
                if not running or destroyed then break end
                moveToPosition(pos, farmSpeed)
                task.wait(0.15)
            end
            task.wait(0.1)
        end
    end)
end, Color3.fromRGB(38, 115, 75))
addButton(waypointSection, "STOP WAYPOINT FARM", stopFarm, Color3.fromRGB(130, 43, 49))

-- FLIGHT (original movement loop retained)
local flightSection = makeSection("Fly")
local flightToggle
flightToggle = addButton(flightSection, "FLIGHT: OFF", function()
    if flying then
        flying = false
        autoFlightTarget = nil
        if flightConnection then flightConnection:Disconnect(); flightConnection = nil end
        if flightVelocity then flightVelocity:Destroy(); flightVelocity = nil end
        if flightGyro then flightGyro:Destroy(); flightGyro = nil end
        if humanoid then humanoid.AutoRotate = true end
        flightToggle.Text = "FLIGHT: OFF"
        flightToggle.BackgroundColor3 = Color3.fromRGB(130, 43, 49)
        return
    end
    updateCharacter()
    if not rootPart or not humanoid then notify("Character not found"); return end
    if running then stopFarm() end
    flying = true
    humanoid.AutoRotate = false
    flightVelocity = Instance.new("BodyVelocity")
    flightVelocity.Name = "AF_FlightVelocity"
    flightVelocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flightVelocity.P = 15000
    flightVelocity.Velocity = Vector3.zero
    flightVelocity.Parent = rootPart
    flightGyro = Instance.new("BodyGyro")
    flightGyro.Name = "AF_FlightGyro"
    flightGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    flightGyro.P = 12000
    flightGyro.D = 700
    flightGyro.CFrame = rootPart.CFrame
    flightGyro.Parent = rootPart
    flightConnection = RunService.Heartbeat:Connect(function()
        if not flying or not rootPart or not humanoid then
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then return end

        local cameraCF = camera.CFrame
        local moveDirection = humanoid.MoveDirection

        -- Camera's horizontal forward and right directions
        local flatForward = Vector3.new(
            cameraCF.LookVector.X,
            0,
            cameraCF.LookVector.Z
        )

        if flatForward.Magnitude < 0.001 then
            flatForward = Vector3.new(
                rootPart.CFrame.LookVector.X,
                0,
                rootPart.CFrame.LookVector.Z
            )
        end

        flatForward = flatForward.Unit

        local flatRight = Vector3.new(
            cameraCF.RightVector.X,
            0,
            cameraCF.RightVector.Z
        )

        if flatRight.Magnitude < 0.001 then
            flatRight = Vector3.new(1, 0, 0)
        end

        flatRight = flatRight.Unit

        if autoFlightTarget then
            local delta = autoFlightTarget - rootPart.Position
            if delta.Magnitude <= 2 then
                autoFlightTarget = nil
                flightVelocity.Velocity = Vector3.zero
            else
                flightVelocity.Velocity = delta.Unit * flightSpeed
            end
        else
            -- Convert joystick movement into camera-relative inputs
            local forwardInput = moveDirection:Dot(flatForward)
            local rightInput = moveDirection:Dot(flatRight)
            local direction = cameraCF.LookVector * forwardInput + flatRight * rightInput
            if direction.Magnitude > 0.05 then
                flightVelocity.Velocity = direction.Unit * flightSpeed
            else
                flightVelocity.Velocity = Vector3.zero
            end
        end

        -- Face camera's horizontal direction
        local faceDirection = flatForward
        flightGyro.CFrame = CFrame.lookAt(
            rootPart.Position,
            rootPart.Position + faceDirection
        )
    end)

    flightToggle.Text = "FLIGHT: ON"
    flightToggle.BackgroundColor3 = Color3.fromRGB(38, 115, 75)
end, Color3.fromRGB(130, 43, 49))

addSlider(flightSection, "FLIGHT SPEED", MIN_SPEED, MAX_FLIGHT_SPEED, flightSpeed, function(value)
    flightSpeed = value
end)

-- MOVEMENT / NOCLIP / JUMP / WALK SPEED
local movementSection = makeSection("Movement")
local noclipButton
noclipButton = addButton(movementSection, "WALL PASS: OFF", function()
    if noclip then
        noclip = false
        if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
        for part, old in pairs(originalCollision) do
            if part and part.Parent then part.CanCollide = old end
        end
        table.clear(originalCollision)
        noclipButton.Text = "WALL PASS: OFF"
        noclipButton.BackgroundColor3 = Color3.fromRGB(43, 54, 77)
    else
        updateCharacter()
        if not character then notify("Character not found"); return end
        noclip = true
        noclipConnection = RunService.Stepped:Connect(function()
            updateCharacter()
            if not noclip or not character then return end
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    if originalCollision[part] == nil then originalCollision[part] = part.CanCollide end
                    part.CanCollide = false
                end
            end
        end)
        noclipButton.Text = "WALL PASS: ON"
        noclipButton.BackgroundColor3 = Color3.fromRGB(38, 115, 75)
    end
end)
noclipButton.Size = UDim2.new(1, 0, 0, 52)
noclipButton.TextSize = 17

local jumpButton
jumpButton = addButton(movementSection, "INFINITE JUMP: OFF", function()
    infiniteJump = not infiniteJump
    jumpButton.Text = infiniteJump and "INFINITE JUMP: ON" or "INFINITE JUMP: OFF"
    jumpButton.BackgroundColor3 = infiniteJump and Color3.fromRGB(38, 115, 75) or Color3.fromRGB(43, 54, 77)
end)
track(UserInputService.JumpRequest, function()
    if infiniteJump and not destroyed then
        updateCharacter()
        if humanoid then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

addButton(movementSection, "WALK SPEED +", function()
    walkSpeed = math.min(MAX_SPEED, walkSpeed + SPEED_STEP)
    updateCharacter()
    if humanoid then humanoid.WalkSpeed = walkSpeed end
    notify("Walk speed: " .. walkSpeed)
end)
addButton(movementSection, "WALK SPEED -", function()
    walkSpeed = math.max(MIN_SPEED, walkSpeed - SPEED_STEP)
    updateCharacter()
    if humanoid then humanoid.WalkSpeed = walkSpeed end
    notify("Walk speed: " .. walkSpeed)
end)

-- DEPTH INCREMENTAL: detect the large circular yellow reward pad dynamically.
-- The detector intentionally rejects small yellow props and narrow decorations.
local function getPadMetrics(part)
    local size = part.Size
    local axes = {
        {vertical = math.abs(part.CFrame.RightVector.Y), thickness = size.X, width = size.Y, depth = size.Z},
        {vertical = math.abs(part.CFrame.UpVector.Y), thickness = size.Y, width = size.X, depth = size.Z},
        {vertical = math.abs(part.CFrame.LookVector.Y), thickness = size.Z, width = size.X, depth = size.Y},
    }
    local best = axes[1]
    for i = 2, #axes do
        if axes[i].vertical > best.vertical then best = axes[i] end
    end
    return best.width, best.depth, best.thickness, best.vertical
end

local function isYellowRewardPad(part)
    if not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then return false end
    if character and part:IsDescendantOf(character) then return false end
    if part.Transparency > 0.35 then return false end

    local c = part.Color
    local brightYellow = c.R >= 0.78 and c.G >= 0.62 and c.B <= 0.38
        and (c.R - c.B) >= 0.42 and (c.G - c.B) >= 0.28
    if not brightYellow then return false end

    local width, depth, thickness, verticalAlignment = getPadMetrics(part)
    local wide = math.max(width, depth)
    local narrow = math.min(width, depth)
    if wide < 12 or wide > 180 or narrow < 12 then return false end
    local roundFootprint = narrow / wide >= 0.72
    local flatDisc = thickness <= narrow * 0.32 and verticalAlignment >= 0.72
    if not roundFootprint or not flatDisc then return false end

    local isDisc = false
    pcall(function() isDisc = part:IsA("Part") and part.Shape == Enum.PartType.Cylinder end)
    local isMeshLike = part:IsA("MeshPart") or part:IsA("UnionOperation")
    return isDisc or isMeshLike or roundFootprint
end

local function findYellowTarget()
    updateCharacter()
    if not rootPart then return nil end
    local best, bestScore = nil, -math.huge
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("BasePart") and isYellowRewardPad(item) then
            local width, depth = getPadMetrics(item)
            local area = width * depth
            local distance = (item.Position - rootPart.Position).Magnitude
            -- Large circular pads score higher; distance breaks close ties.
            local score = area - distance * 0.18
            if item:IsA("Part") and item.Shape == Enum.PartType.Cylinder then score += 900 end
            if score > bestScore then best, bestScore = item, score end
        end
    end
    return best
end

local autoSection = makeSection("Auto Farm")
local targetStatus = label(autoSection, "Target: scanning for the large yellow circle", UDim2.new(1, 0, 0, 30), UDim2.new(), 10)
targetStatus.TextXAlignment = Enum.TextXAlignment.Left
local autoButton
autoButton = addButton(autoSection, "AUTO FARM: OFF", function()
    autoFarm = not autoFarm
    autoButton.Text = autoFarm and "AUTO FARM: ON" or "AUTO FARM: OFF"
    autoButton.BackgroundColor3 = autoFarm and Color3.fromRGB(38, 115, 75) or Color3.fromRGB(43, 54, 77)

    if autoFarm then
        task.spawn(function()
            while autoFarm and not destroyed do
                updateCharacter()
                if not rootPart or not humanoid then
                    targetStatus.Text = "Target: character not found"
                    task.wait(0.15)
                else
                    local target = findYellowTarget()
                    if target and target.Parent then
                        local _, _, thickness = getPadMetrics(target)
                        local destination = target.Position + Vector3.new(0, thickness / 2 + 2.5, 0)
                        targetStatus.Text = "Target: large yellow circle locked"

                        -- Record each newly discovered pad location in the history list.
                        local lastSaved = waypoints[#waypoints]
                        if not lastSaved or (lastSaved - target.Position).Magnitude > 8 then
                            table.insert(waypoints, target.Position)
                            if #waypoints > 100 then table.remove(waypoints, 1) end
                            if history.Visible then refreshHistory() end
                        end

                        if movementMode == "Teleport" then
                            if (rootPart.Position - destination).Magnitude > 3 then
                                rootPart.CFrame = CFrame.new(destination)
                            end
                        else
                            humanoid.WalkSpeed = walkSpeed
                            humanoid:MoveTo(destination)
                        end
                        -- Re-scan rapidly: the pad may disappear and respawn elsewhere.
                        -- Do not wait on the old instance for several seconds.
                        task.wait(0.09)
                    else
                        targetStatus.Text = "Target: waiting for the yellow circle"
                        task.wait(0.12)
                    end
                end
            end
        end)
    else
        targetStatus.Text = "Target: auto farm stopped"
    end
end, Color3.fromRGB(43, 54, 77))
autoButton.Size = UDim2.new(1, 0, 0, 48)
autoButton.TextSize = 15

-- Lightning event detector for the "Catch the Lightning" room.
-- The event is visually represented by a bright yellow circular pad inside
-- the large gold ring, with a vertical yellow lightning beam when active.
-- The beam itself may be a Beam/Particle object rather than a BasePart, so
-- the bright circular pad is used as the stable movement target.
local function findLightningPortalAnchor()
    updateCharacter()
    if not rootPart then return nil end

    local bestPosition, bestDistance = nil, math.huge
    for _, item in ipairs(Workspace:GetDescendants()) do
        local searchText = string.lower(item.Name or "")
        if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
            pcall(function()
                searchText = searchText .. " " .. string.lower(item.Text or "")
            end)
        end

        if string.find(searchText, "catch the lightning", 1, true)
            or string.find(searchText, "catchthelightning", 1, true) then
            local ancestor = item
            for _ = 1, 15 do
                if not ancestor then break end
                if ancestor:IsA("BasePart") then
                    local distance = (ancestor.Position - rootPart.Position).Magnitude
                    if distance < bestDistance then
                        bestPosition, bestDistance = ancestor.Position, distance
                    end
                    break
                elseif ancestor:IsA("Model") then
                    local ok, pivot = pcall(function() return ancestor:GetPivot() end)
                    if ok and pivot then
                        local distance = (pivot.Position - rootPart.Position).Magnitude
                        if distance < bestDistance then
                            bestPosition, bestDistance = pivot.Position, distance
                        end
                    end
                end
                ancestor = ancestor.Parent
            end
        end
    end
    return bestPosition
end

local function findLightningTarget()
    updateCharacter()
    if not rootPart then return nil end

    -- Never search globally: the Catch the Lightning portal must be found first.
    local portalPosition = findLightningPortalAnchor()
    if not portalPosition then return nil end

    local bestPart, bestScore, bestThickness = nil, -math.huge, 0
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("BasePart") and isYellowRewardPad(item) then
            local width, depth, thickness = getPadMetrics(item)
            local diameter = math.max(width, depth)
            local distanceFromPortal = (item.Position - portalPosition).Magnitude
            if distanceFromPortal <= 100 and diameter >= 12 and diameter <= 85 then
                local distance = (item.Position - rootPart.Position).Magnitude
                local score = 1000 - distance * 0.10 - distanceFromPortal * 0.35
                if item.Material == Enum.Material.Neon then score += 100 end
                if item:IsA("Part") and item.Shape == Enum.PartType.Cylinder then score += 120 end
                if score > bestScore then
                    bestPart, bestScore, bestThickness = item, score, thickness
                end
            end
        end
    end

    if bestPart then
        return bestPart.Position + Vector3.new(0, bestThickness / 2 + 2.5, 0), "Catch the Lightning center"
    end
    return nil
end

local function moveToWorldTarget(position, useFlightSpeed)
    updateCharacter()
    if not rootPart or not humanoid or not position then return end
    if movementMode == "Teleport" then
        autoFlightTarget = nil
        if (rootPart.Position - position).Magnitude > 1.5 then
            rootPart.CFrame = CFrame.new(position)
        end
    elseif flying and flightVelocity then
        autoFlightTarget = position
    else
        humanoid.WalkSpeed = useFlightSpeed and math.max(walkSpeed, 90) or walkSpeed
        humanoid:MoveTo(position)
    end
end

-- LIGHTNING: highest-priority collector; scan frequently and move to its center.
local lightningSection = makeSection("Lightning")
local lightningStatus = label(lightningSection, "Priority: HIGH  |  Status: scanning", UDim2.new(1, 0, 0, 34), UDim2.new(), 10)
lightningStatus.TextXAlignment = Enum.TextXAlignment.Left
local lightningButton
lightningButton = addButton(lightningSection, "AUTO COLLECT LIGHTNING: OFF", function()
    lightningEnabled = not lightningEnabled
    lightningButton.Text = lightningEnabled and "AUTO COLLECT LIGHTNING: ON" or "AUTO COLLECT LIGHTNING: OFF"
    lightningButton.BackgroundColor3 = lightningEnabled and Color3.fromRGB(38, 115, 75) or Color3.fromRGB(43, 54, 77)
    if lightningEnabled then
        task.spawn(function()
            while lightningEnabled and not destroyed do
                local pos, targetName = findLightningTarget()
                if pos then
                    lightningStatus.Text = "LOCKED: " .. tostring(targetName) .. "  |  moving to center"
                    -- Teleport mode reaches the spawn center immediately; walk/flight uses boosted speed.
                    moveToWorldTarget(pos, true)
                else
                    lightningStatus.Text = "Priority: HIGH  |  waiting for lightning spawn"
                end
                task.wait(0.04)
            end
        end)
    else
        autoFlightTarget = nil
        lightningStatus.Text = "Status: lightning collector stopped"
    end
end, Color3.fromRGB(130, 90, 35))

local lightningNote = label(lightningSection,
    "Only searches near the Catch the Lightning portal. Moves to the center of the active yellow lightning circle and follows it when it respawns.",
    UDim2.new(1, 0, 0, 58), UDim2.new(), 10)
lightningNote.TextColor3 = Color3.fromRGB(175, 181, 193)
lightningNote.TextXAlignment = Enum.TextXAlignment.Left

-- TELEPORT TO PLAYER ONCE PER PRESS
local playerSection = makeSection("Player")
local userBox = Instance.new("TextBox")
userBox.Size = UDim2.new(1, 0, 0, 36)
userBox.BackgroundColor3 = Color3.fromRGB(30, 39, 57)
userBox.PlaceholderText = "Enter player username"
userBox.Text = ""
userBox.TextColor3 = Color3.new(1,1,1)
userBox.PlaceholderColor3 = Color3.fromRGB(160, 170, 190)
userBox.Font = Enum.Font.Gotham
userBox.TextSize = 13
userBox.ClearTextOnFocus = false
userBox.Parent = playerSection
round(userBox, 7)

addButton(playerSection, "TELEPORT TO PLAYER", function()
    local query = string.lower((userBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if query == "" then notify("Enter a username first"); return end
    local targetPlayer
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.Name) == query or string.lower(p.DisplayName) == query then
            targetPlayer = p
            break
        end
    end
    if not targetPlayer then notify("Player not found in this server"); return end
    updateCharacter()
    local targetChar = targetPlayer.Character
    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not rootPart or not targetRoot then notify("Character not ready"); return end
    rootPart.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 4)
    notify("Teleported to " .. targetPlayer.Name)
end)

-- DRAG WINDOW
local locked = false
local dragging, dragStart, startPos = false, nil, nil
track(lockButton.MouseButton1Click, function()
    locked = not locked
    lockButton.Text = locked and "🔒" or "🔓"
end)
track(header.InputBegan, function(input)
    if locked then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end
end)
track(UserInputService.InputChanged, function(input)
    if dragging and not locked and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
track(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
end)

-- The location-history window can be moved independently from the main menu.
local historyDragging, historyDragStart, historyStartPos = false, nil, nil
track(historyHeader.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        historyDragging = true
        historyDragStart = input.Position
        historyStartPos = history.Position
    end
end)
track(UserInputService.InputChanged, function(input)
    if historyDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - historyDragStart
        history.Position = UDim2.new(historyStartPos.X.Scale, historyStartPos.X.Offset + delta.X, historyStartPos.Y.Scale, historyStartPos.Y.Offset + delta.Y)
    end
end)
track(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then historyDragging = false end
end)

-- Minimize / restore
local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(50, 50)
mini.Position = UDim2.new(1, -68, 0.18, 0)
mini.Text = "AF"
mini.TextColor3 = Color3.new(1,1,1)
mini.Font = Enum.Font.GothamBold
mini.TextSize = 17
mini.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
mini.Visible = false
mini.Parent = gui
round(mini, 12)
outline(mini, Color3.fromRGB(80, 125, 190), 2)

track(closeButton.MouseButton1Click, function()
    main.Visible = false
    mini.Visible = true
end)
track(mini.MouseButton1Click, function()
    mini.Visible = false
    main.Visible = true
end)

-- Cleanup
track(player.CharacterRemoving, function()
    if flying then
        flying = false
        if flightConnection then flightConnection:Disconnect(); flightConnection = nil end
        if flightVelocity then flightVelocity:Destroy(); flightVelocity = nil end
        if flightGyro then flightGyro:Destroy(); flightGyro = nil end
    end
end)

notify("AUTO FARM PRO loaded")
