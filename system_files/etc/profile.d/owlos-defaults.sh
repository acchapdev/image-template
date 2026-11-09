# shellcheck shell=sh
# owlOS default terminal. greetd sources /etc/profile before starting a session,
# so this reaches the compositor and Dux (`dms run`), which uses $TERMINAL
# unless a terminal is picked in Dux Settings. Users can override it.
export TERMINAL="${TERMINAL:-ghostty}"
