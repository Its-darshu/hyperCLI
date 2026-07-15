#!/usr/bin/env bash
# wifi-menu.sh — WiFi network selector and toggle using fuzzel

# Get current WiFi status from NetworkManager
wifi_state=$(nmcli radio wifi)

if [ "$wifi_state" = "disabled" ]; then
    # WiFi is OFF
    selection=$(echo -e "󰖩  Turn WiFi ON" | fuzzel -d -p "WiFi: " -w 30 -l 1)
    if [ "$selection" = "󰖩  Turn WiFi ON" ]; then
        nmcli radio wifi on
        notify-send -u normal -i network-wireless "WiFi Enabled" "WiFi radio has been turned on"
    fi
else
    # WiFi is ON
    # Scan for networks in the background to refresh cache
    nmcli dev wifi rescan &>/dev/null &
    
    # Read the current cached list
    raw_list=$(nmcli -t -f "IN-USE,SSID,SIGNAL,BARS,SECURITY" device wifi list)
    
    # Build the selection menu options
    display_lines=("󰖪  Turn WiFi OFF")
    action_types=("toggle_off")
    action_ssids=("")
    
    declare -A seen_ssids
    
    while IFS=: read -r in_use ssid signal bars security; do
        [ -z "$ssid" ] && continue
        [ "$ssid" = "--" ] && continue
        
        # Check if we've already seen this SSID
        if [ "${seen_ssids[$ssid]}" ]; then
            continue
        fi
        seen_ssids[$ssid]=1
        
        # Format security
        if [ -n "$security" ] && [ "$security" != "--" ]; then
            sec_label="$security"
        else
            sec_label="Open"
        fi
        
        if [ "$in_use" = "*" ]; then
            display_lines+=("󰄬  $ssid [Connected] ($sec_label)")
            action_types+=("disconnect")
            action_ssids+=("$ssid")
        else
            display_lines+=("   $ssid ($bars) ($sec_label)")
            if [ "$sec_label" = "Open" ]; then
                action_types+=("connect_open")
            else
                action_types+=("connect_secure")
            fi
            action_ssids+=("$ssid")
        fi
    done <<< "$raw_list"
    
    # Join array elements with newlines for fuzzel input
    IFS=$'\n'
    menu_input="${display_lines[*]}"
    unset IFS
    
    # Launch fuzzel in dmenu mode and print the selected option's index
    selected_index=$(echo -e "$menu_input" | fuzzel -d --index -p "WiFi: " -w 50 -l 12)
    
    if [ -z "$selected_index" ]; then
        exit 0
    fi
    
    action="${action_types[$selected_index]}"
    ssid="${action_ssids[$selected_index]}"
    
    case "$action" in
        toggle_off)
            nmcli radio wifi off
            notify-send -u normal -i network-wireless-offline "WiFi Disabled" "WiFi radio has been turned off"
            ;;
        disconnect)
            # Find the active connection name and bring it down
            active_conn=$(nmcli -t -f ACTIVE,NAME connection show | grep "^yes:" | cut -d: -f2- | head -n1)
            if [ -n "$active_conn" ]; then
                nmcli connection down id "$active_conn"
            else
                # Fallback: disconnect by interface
                dev=$(nmcli -t -f DEVICE,TYPE device | grep :wifi | head -n1 | cut -d: -f1)
                nmcli device disconnect "$dev"
            fi
            notify-send -u normal -i network-wireless-offline "WiFi Disconnected" "Disconnected from $ssid"
            ;;
        connect_open)
            notify-send "WiFi" "Connecting to open network: $ssid..."
            if nmcli device wifi connect "$ssid"; then
                notify-send -u normal -i network-wireless "WiFi Connected" "Successfully connected to $ssid"
            else
                notify-send -u critical -i network-wireless-error "Connection Failed" "Could not connect to $ssid"
            fi
            ;;
        connect_secure)
            # Check if connection profile already exists and try connecting using it first
            if nmcli connection show | grep -F -w "$ssid" &>/dev/null; then
                notify-send "WiFi" "Connecting to saved network: $ssid..."
                if nmcli connection up id "$ssid" &>/dev/null; then
                    notify-send -u normal -i network-wireless "WiFi Connected" "Successfully connected to $ssid"
                    exit 0
                fi
            fi
            
            # Prompt for password using fuzzel in password mode (input characters masked)
            password=$(fuzzel -d --password -p "Enter password for $ssid: " -w 40 -l 0)
            if [ -z "$password" ]; then
                exit 0
            fi
            notify-send "WiFi" "Connecting to $ssid..."
            if nmcli device wifi connect "$ssid" password "$password"; then
                notify-send -u normal -i network-wireless "WiFi Connected" "Successfully connected to $ssid"
            else
                notify-send -u critical -i network-wireless-error "Connection Failed" "Could not connect to $ssid"
            fi
            ;;
    esac
fi
