#!/bin/bash
# Removes the auto-start service (the project files and voices are kept).
LABEL="com.freewilllawyer.voice"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
echo "Servicio desinstalado. El servidor ya no arrancará solo."
read -n 1 -s -r -p "Presiona cualquier tecla para cerrar..."
