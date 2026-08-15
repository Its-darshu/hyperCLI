# Autoloaded by fish at key-binding setup time. This must NOT live in config.fish —
# fish builds its bindings before config.fish is sourced, so a definition there is
# simply never called.
function fish_user_key_bindings
    # Tab fills the suggestion in place instead of popping the completion pager.
    bind tab __tab_autofill
    bind --mode insert tab __tab_autofill
end
