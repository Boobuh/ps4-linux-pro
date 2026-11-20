#!/bin/sh
# psxitarch: XFCE + Ubuntu look via startx (X server already running).
command -v polkit-gnome-authentication-agent-1 >/dev/null &&
  polkit-gnome-authentication-agent-1 &

export DESKTOP_SESSION=xfce
export XDG_CURRENT_DESKTOP=XFCE
export XDG_MENU_PREFIX=xfce-

# Ubuntu-style GTK (global + XFCE channel filled on first session start)
export GTK_THEME=Adwaita-dark
export XCURSOR_THEME=Adwaita

if command -v startxfce4 >/dev/null 2>&1; then
  exec startxfce4
fi
exec /usr/bin/jwm