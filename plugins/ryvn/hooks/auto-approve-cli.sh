#!/bin/bash
# Auto-approve ryvn CLI commands

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# Auto-approve ryvn CLI commands
reject_pattern='[;&|$`><(){}]'
if [[ "$command" =~ ^ryvn[[:space:]] ]] && ! [[ "$command" =~ $reject_pattern ]]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Ryvn CLI command auto-approved"
  }
}
EOF
  exit 0
fi

exit 0
