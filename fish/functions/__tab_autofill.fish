# Tab = autofill, not a completion list.
#
# Fish's inline (grey) autosuggestion already draws on history, valid paths and
# completions, so accept it in place rather than opening the pager. The pager is
# only reached when there is no inline suggestion to fill in — at that point a
# list is the only thing Tab could usefully do anyway.
#
# `commandline --showing-suggestion` needs fish >= 3.7 (running 4.2).
function __tab_autofill --description 'Tab: accept the inline autosuggestion, else complete'
    if commandline --showing-suggestion
        commandline -f accept-autosuggestion
    else
        commandline -f complete
    end
end
