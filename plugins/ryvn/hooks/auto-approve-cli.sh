#!/bin/bash
# Auto-approve Ryvn CLI commands. An "allow" covers the whole Bash string, so a
# payload is approved only when it is exactly one ryvn command. Quoted arguments
# are data (inline JSON patches with `{}` or `;` are fine); anything that
# chains, substitutes, redirects, groups, or comments at the top level falls
# through to the normal prompt.

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# The first word must be the literal, unquoted name: `"rm" ryvn` runs rm.
[[ "$command" =~ ^ryvn([[:space:]]|$) ]] || exit 0

# Substitution fires even inside double quotes, so check the raw string first.
case "$command" in
  *\$\(* | *\`* | *\$\{*) exit 0 ;;
esac

# Keep only the characters bash parses as structure by dropping quoted spans
# and backslash-escaped characters, tracking quote state the way bash does.
skeleton=""
state=unquoted
i=0
len=${#command}
while ((i < len)); do
  char=${command:i:1}
  case "$state" in
    unquoted)
      case "$char" in
        \\)
          ((i + 1 < len)) || exit 0
          ((i++))
          ;;
        "'") state=single ;;
        '"') state=double ;;
        '$')
          # $'...' and $"..." quote differently from plain quotes; don't guess.
          [[ "${command:i+1:1}" == [\'\"] ]] && exit 0
          skeleton+="$char"
          ;;
        *) skeleton+="$char" ;;
      esac
      ;;
    single)
      [[ "$char" == "'" ]] && state=unquoted
      ;;
    double)
      case "$char" in
        \\)
          ((i + 1 < len)) || exit 0
          ((i++))
          ;;
        '"') state=unquoted ;;
      esac
      ;;
  esac
  ((i++))
done

[[ "$state" == unquoted ]] || exit 0

# Any metacharacter or control character (newlines included) left at the top
# level means more than one simple command.
case "$skeleton" in
  *';'* | *'|'* | *'&'* | *'<'* | *'>'* | *'#'* | *'('* | *')'* | *'{'* | *'}'*) exit 0 ;;
esac
[[ "${skeleton//$'\t'/}" =~ [[:cntrl:]] ]] && exit 0

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
