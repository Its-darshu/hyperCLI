# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors — disabled: this re-applied quickshell's peach palette at runtime
    # via OSC escapes, overriding the terminal's own theme on every new shell.
    # if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    #     cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    # end

    # Tab = autofill, not a completion list. See functions/fish_user_key_bindings.fish
    # (it must live there: fish sets up key bindings before config.fish is sourced).

    # Aliases
    # Some terminals don't clear scrollback, so we use explicit ANSI escapes
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    if test "$TERM" != "linux"
        alias ls 'eza --icons'
    end

    # System info banner on every new terminal
    if type -q fastfetch
        fastfetch
    end
end


# Added by Antigravity CLI installer
set -gx PATH "/home/jocky/.local/bin" $PATH
