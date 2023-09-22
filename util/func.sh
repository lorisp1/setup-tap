readVariableWithDefault() {
  local variable
  read -r -p "$1 [$2]: " variable
  variable=${variable:=$2}
  echo "$variable"
}