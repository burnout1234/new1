-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text)
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function findNearestPlayers(count)
    local me = LatestGameState.Players[ao.id]

    local nearestPlayers = {}
    local distances = {}

    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local other = state;
        local xdiff = me.x - other.x
        local ydiff = me.y - other.y
        local distance = math.sqrt(xdiff * xdiff + ydiff * ydiff)

        table.insert(distances, { player = other, distance = distance })
        ::continue::
    end

    table.sort(distances, function(a, b) return a.distance < b.distance end)

    for i = 1, count do
        if distances[i] then
            table.insert(nearestPlayers, distances[i].player)
        end
    end

    return nearestPlayers
end

directionMap = {}
directionMap[{ x = 0, y = 1 }] = "Up"
directionMap[{ x = 0, y = -1 }] = "Down"
directionMap[{ x = -1, y = 0 }] = "Left"
directionMap[{ x = 1, y = 0 }] = "Right"
directionMap[{ x = 1, y = 1 }] = "UpRight"
directionMap[{ x = -1, y = 1 }] = "UpLeft"
directionMap[{ x = 1, y = -1 }] = "DownRight"
directionMap[{ x = -1, y = -1 }] = "DownLeft"

function findAvoidDirection()
    local me = LatestGameState.Players[ao.id]

    local avoidDirection = { x = 0, y = 0 }
    for target, state in pairs(LatestGameState.Players) do
        if target == ao.id then
            goto continue
        end

        local otherPlayer = state
        local avoidVector = { x = me.x - otherPlayer.x, y = me.y - otherPlayer.y }
        avoidDirection.x = avoidDirection.x + avoidVector.x
        avoidDirection.y = avoidDirection.y + avoidVector.y

        ::continue::
    end
    avoidDirection = normalizeDirection(avoidDirection)

    local closestDirection = nil
    local closestDotResult = nil

    for direction, name in pairs(directionMap) do
        local normalized = normalizeDirection(direction)
        local dotResult = avoidDirection.x * normalized.x + avoidDirection.y + normalized.y

        if closestDirection == nil or closestDotResult < dotResult then
            closestDirection = name
            closestDotResult = dotResult
        end
    end

    return closestDirection
end

function findApproachDirection()
    local me = LatestGameState.Players[ao.id]

    local approachDirection = { x = 0, y = 0 }
    local otherPlayer = findNearestPlayers(1)[1]
    local approachVector = { x = otherPlayer.x - me.x, y = otherPlayer.y - me.y }
    approachDirection.x = approachDirection.x + approachVector.x
    approachDirection.y = approachDirection.y + approachVector.y
    approachDirection = normalizeDirection(approachDirection)

    local closestDirection = nil
    local closestDotResult = nil

    for direction, name in pairs(directionMap) do
        local normalized = normalizeDirection(direction)
        local dotResult = approachDirection.x * normalized.x + approachDirection.y + normalized.y

        if closestDirection == nil or closestDotResult < dotResult then
            closestDirection = name
            closestDotResult = dotResult
        end
    end

    return closestDirection
end

function isPlayerInAttackRange(player)
    local me = LatestGameState.Players[ao.id]

    if inRange(me.x, me.y, player.x, player.y, 1) then
        return true;
    end

    return false;
end

function normalizeDirection(direction)
    local length = math.sqrt(direction.x * direction.x + direction.y * direction.y)
    return { x = direction.x / length, y = direction.y / length }
end

function decideNextAction()
    local me = LatestGameState.Players[ao.id]

    local nearestPlayers = findNearestPlayers(3)
    local isAnyPlayerInAttackRange = false

    for _, player in ipairs(nearestPlayers) do
        if isPlayerInAttackRange(player) then
            isAnyPlayerInAttackRange = true
            break
        end
    end

    if not isAnyPlayerInAttackRange then
        local approachDirection = findApproachDirection()
        print(colors.blue .. "Being aggressive. Approaching." .. colors.reset)
        ao.send({ Target = Game, Action = "PlayerMove", Player = ao.id, Direction = approachDirection })
        InAction = false
    else
        for _, player in ipairs(nearestPlayers) do
            if isPlayerInAttackRange(player) then
                -- Attack with full energy
                print(colors.red .. "Attacking player with ID: " .. player.id .. " with full energy." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, TargetPlayer = player.id, AttackEnergy = tostring(me.energy) })
                InAction = false
                break
            end
        end
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
    "PrintAnnouncements",
    Handlers.utils.hasMatchingTag("Action", "Announcement"),
    function(msg)
        if msg.Event == "Started-Waiting-Period" then
            ao.send({ Target = ao.id, Action = "AutoPay" })
        elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
            InAction = true
            ao.send({ Target = Game, Action = "GetGameState" })
        elseif InAction then
            print("Previous action still in progress. Skipping.")
        end

        print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
    end
)

-- Handler to trigger game state updates.
Handlers.add(
    "GetGameStateOnTick",
    Handlers.utils.hasMatchingTag("Action", "Tick"),
    function()
        if not InAction then
            InAction = true
            print(colors.gray .. "Getting game state..." .. colors.reset)
            ao.send({ Target = Game, Action = "GetGameState" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
    "AutoPay",
    Handlers.utils.hasMatchingTag("Action", "AutoPay"),
    function(msg)
        print("Auto-paying confirmation fees.")
        ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000" })
    end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
    "UpdateGameState",
    Handlers.utils.hasMatchingTag("Action", "GameState"),
    function(msg)
        local json = require("json")
        LatestGameState = json.decode(msg.Data)
        ao.send({ Target = ao.id, Action = "UpdatedGameState" })
        print("Game state updated. Print \'LatestGameState\' for detailed view.")
        print("energy:" .. LatestGameState.Players[ao.id].energy)
    end
)

-- Handler to decide the next best action.
Handlers.add(
    "decideNextAction",
    Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
    function()
        if LatestGameState.GameMode ~= "Playing" then
            print("Game not started")
            InAction = false
            return
        end
        print("Deciding next action.")
        decideNextAction()
        ao.send({ Target = ao.id, Action = "Tick" })
    end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
    "ReturnAttack",
    Handlers.utils.hasMatchingTag("Action", "Hit"),
    function(msg)
        if not InAction then
            InAction = true
            local playerEnergy = LatestGameState.Players[ao.id].energy
            if playerEnergy == nil then
                print(colors.red .. "Unable to read energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy." })
            elseif playerEnergy == 0 then
                print(colors.red .. "Player has insufficient energy." .. colors.reset)
                ao.send({ Target = Game, Action = "Attack-Failed", Reason = "Player has no energy." })
            else
                print(colors.red .. "Returning attack." .. colors.reset)
                ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy) })
            end
            InAction = false
            ao.send({ Target = ao.id, Action = "Tick" })
        else
            print("Previous action still in progress. Skipping.")
        end
    end
)
