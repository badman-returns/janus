# Source at the top of every scheduled job. A pause is a file; presence means stop reading anything new.
[ -e "$HOME/.brain/PAUSED" ] && exit 0
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
