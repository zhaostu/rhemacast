#!/bin/sh
while grep -qE '^\- \[ \]' PROMPT.md; do
  claude --dangerously-skip-permissions -p "$(cat PROMPT.md)"
  echo "--- Task complete. Starting next task ---"
done
echo "All tasks complete!"
