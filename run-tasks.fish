#!/usr/bin/env fish
# Runs each unchecked todo.md task in a fresh pi process (new context each time).
# Stops when all tasks are done, a run fails, or a task isn't ticked
# (e.g. it needs user input; finish that one interactively with `pi`, then rerun).

cd (dirname (status filename))

set prompt 'Read todo.md. Do ONLY the first unchecked task (- [ ]). Verify it works, then tick it in todo.md and append a short handoff note under "## Notes / risks" for the next agent. Do not commit. If the task needs input from the user (e.g. pressing a key), do not tick it; explain what is needed and stop. Then stop.'

while grep -q -- '- \[ \]' todo.md
    set before (grep -c -- '- \[x\]' todo.md)
    echo "=== Next task ==="
    pi -p $prompt; or begin; echo "pi failed, stopping."; exit 1; end
    set after (grep -c -- '- \[x\]' todo.md)
    if test $after -le $before
        echo "Task not ticked, stopping."
        exit 1
    end
end

echo "All tasks done."
