module("luci.controller.connected_devices", package.seeall)

function index()
    entry({"admin", "network", "connected_devices"}, call("action_devices"), _("Connected Devices"), 60)
    entry({"admin", "network", "connected_devices", "full"}, call("action_devices_full"), _("Full Device List"), 61)
end

function action_devices()
    local devices, networks = get_connected_devices(false)
    luci.template.render("connected_devices", {devices = devices, networks = networks})
end

function action_devices_full()
    local devices, networks = get_connected_devices(true)
    luci.template.render("connected_devices", {devices = devices, networks = networks})
end

-- Debug logging function
function log_debug(msg)
    local f = io.open("/tmp/luci_debug.log", "a")
    if f then
        f:write(msg .. "\n")
        f:close()
    end
end

function get_connected_devices(full_list)
    local devices = {}
    local networks = {"Ethernet"}
    local seen_macs = {}

    log_debug("Fetching connected devices...")

    -- Fetch DHCP leases
    local leases_handle = io.open("/tmp/dhcp.leases", "r")
    if leases_handle then
        log_debug("Reading /tmp/dhcp.leases...")
        for line in leases_handle:lines() do
            log_debug("Lease line: " .. line)
            local timestamp, mac, lease_ip, hostname = line:match("(%d+)%s+(%x+:%x+:%x+:%x+:%x+:%x+)%s+(%d+%.%d+%.%d+%.%d+)%s+(%S*)")
            if lease_ip and mac then
                hostname = (hostname and hostname ~= "*") and hostname or "ip-" .. lease_ip
                devices[mac] = {ip = lease_ip, mac = mac, hostname = hostname, network = "Ethernet"}
                seen_macs[mac] = true
                log_debug("Added DHCP lease: " .. mac .. " - " .. lease_ip .. " - " .. hostname)
            end
        end
        leases_handle:close()
    else
        log_debug("Failed to read /tmp/dhcp.leases!")
    end

    -- Fetch Wi-Fi interfaces
    local wifi_interfaces = {}
    local wifi_handle = io.popen("iw dev | awk '/Interface/ {print $2}'")
    if wifi_handle then
        log_debug("Detecting Wi-Fi interfaces...")
        for interface in wifi_handle:read("*a"):gmatch("(%S+)") do
            table.insert(wifi_interfaces, interface)
            log_debug("Found Wi-Fi interface: " .. interface)
        end
        wifi_handle:close()
    else
        log_debug("Failed to get Wi-Fi interfaces!")
    end

    -- Identify Wi-Fi networks and categorize devices
    for _, interface in ipairs(wifi_interfaces) do
        local essid = get_essid(interface) or "Unknown Wi-Fi"
        log_debug("ESSID for " .. interface .. ": " .. essid)
        
        if not table_contains(networks, essid) then
            table.insert(networks, essid)
        end

        local assoc_handle = io.popen("iw dev " .. interface .. " station dump | awk '/Station/ {print $2}'")
        if assoc_handle then
            log_debug("Checking associated stations on " .. interface)
            for mac in assoc_handle:read("*a"):gmatch("(%x+:%x+:%x+:%x+:%x+:%x+)") do
                log_debug("Detected Wi-Fi MAC: " .. mac)
                
                -- If the MAC is in DHCP leases, update the network name
                if devices[mac] then
                    devices[mac].network = essid
                else
                    -- If the MAC isn't in DHCP leases, add it as a new device
                    devices[mac] = {ip = "Unknown", mac = mac, hostname = "Unknown", network = essid}
                end
            end
            assoc_handle:close()
        else
            log_debug("Failed to get associated stations for " .. interface)
        end
    end

    -- Convert devices table to an indexed array
    local devices_list = {}
    for _, device in pairs(devices) do
        log_debug("Final device: " .. device.mac .. " - " .. device.ip .. " - " .. device.hostname .. " - " .. device.network)
        if full_list or device.network ~= "Unknown" then
            table.insert(devices_list, device)
        end
    end

    log_debug("Finished fetching devices. Total: " .. #devices_list)

    return devices_list, networks
end

-- Get ESSID of a Wi-Fi interface
function get_essid(interface)
    local essid_handle = io.popen("iw dev " .. interface .. " info | awk '/ssid/ {print $2}'")
    if essid_handle then
        local essid = essid_handle:read("*a"):gsub("%s+", "") -- Trim whitespace
        essid_handle:close()
        return essid ~= "" and essid or nil
    end
    return nil
end

-- Utility function to check if a value exists in a table
function table_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end
