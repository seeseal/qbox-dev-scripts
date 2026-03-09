-- ============================================
--  fd_dealership | client.lua
--  Handles player interaction and UI communication
-- ============================================

local isUIOpen = false

-- ============================================
--  Target Zone
--  Creates the interaction point at the dealership
--  Player walks up and presses E to open the UI
-- ============================================

CreateThread(function()
    -- Wait for ox_target to load
    Wait(2000)

    exports.ox_target:addSphereZone({
        coords  = Config.Location,
        radius  = 5.0,
        options = {
            {
                label   = "Browse " .. Config.DealershipName,
                icon    = "fas fa-car",
                onSelect = function()
                    if isUIOpen then return end
                    -- Request catalog from server
                    TriggerServerEvent('fd_dealership:server:getCatalog')
                end
            }
        }
    })
end)

-- ============================================
--  Open UI
--  Server sends catalog data back after getCatalog
-- ============================================

RegisterNetEvent('fd_dealership:client:openUI', function(data)
    if isUIOpen then return end
    isUIOpen = true

    -- Send data to NUI
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = "openDealership",
        data    = data,
        tiers   = Config.Tiers,
        categories = Config.Categories,
        dealershipName = Config.DealershipName,
    })
end)

-- ============================================
--  Close UI
--  Called by server after successful purchase
--  or by player pressing ESC / close button
-- ============================================

RegisterNetEvent('fd_dealership:client:closeUI', function()
    closeUI()
end)

function closeUI()
    if not isUIOpen then return end
    isUIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeUI" })
end

-- ============================================
--  NUI Callbacks
--  Messages sent from the HTML/JS to Lua
-- ============================================

-- Player clicked Purchase on a vehicle
RegisterNUICallback('purchaseVehicle', function(data, cb)
    TriggerServerEvent('fd_dealership:server:purchase', data.model)
    cb('ok')
end)

-- Player closed the UI manually
RegisterNUICallback('closeUI', function(_, cb)
    closeUI()
    cb('ok')
end)

-- ============================================
--  ESC key to close UI
-- ============================================

CreateThread(function()
    while true do
        Wait(0)
        if isUIOpen then
            if IsControlJustPressed(0, 200) then -- 200 = ESC
                closeUI()
            end
        else
            Wait(500)
        end
    end
end)

print("^2[fd_dealership] Client loaded.^0")
```

---

Save and push.

Commit message:
```
