# Source this file to define the swap-caps alias:
#   source ~/dot_files/bin/swap-ctrl-caps.zsh
#   swap-caps

swap-caps() {
  sudo loadkeys << 'EOF'
keymaps 0-15
keycode 29 = Control
keycode 58 = Caps_Lock
EOF
}

swap-both-ctrl() {
  sudo loadkeys << 'EOF'
keymaps 0-15
keycode 29 = Control
keycode 58 = Control
EOF
}

alias swap-ctrl-caps='swap-caps'
