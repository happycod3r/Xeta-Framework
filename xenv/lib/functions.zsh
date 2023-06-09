function zsh_stats() {
  
}

function open_command() {
    local open_cmd

    # define the open command
    case "$OSTYPE" in
        darwin*)  
            open_cmd='open' 
        ;;
        cygwin*)  
            open_cmd='cygstar t' 
        ;;
        linux*)   
            [[ "$(uname -r)" != *icrosoft* ]] && open_cmd='nohup xdg-open' || {
                open_cmd='cmd.exe /c start ""'
                [[ -e "$1" ]] && { 
                    1="$(wslpath -w "${1:a}")" || return 1 
                    }
            } 
        ;;
        msys*)    
            open_cmd='start ""' 
        ;;
        *)      
            echo "Platform $OSTYPE not supported"
            return 1
        ;;
    esac

    # If a URL is passed, $BROWSER might be set to a local browser within SSH.
    # See https://github.com/xeta/xeta/issues/11098
    if [[ -n "$BROWSER" && "$1" = (http|https)://* ]]; then
        "$BROWSER" "$@"
        return
    fi

    ${=open_cmd} "$@" &>/dev/null
}

# take functions

# mkcd is equivalent to takedir
function mkcd takedir() {
  mkdir -p $@ && cd ${@:$#}
}

function takeurl() {
  local data thedir
  data="$(mktemp)"
  curl -L "$1" > "$data"
  tar xf "$data"
  thedir="$(tar tf "$data" | head -n 1)"
  rm "$data"
  cd "$thedir"
}

function takegit() {
  git clone "$1"
  cd "$(basename ${1%%.git})"
}

function take() {
  if [[ $1 =~ ^(https?|ftp).*\.(tar\.(gz|bz2|xz)|tgz)$ ]]; then
    takeurl "$1"
  elif [[ $1 =~ ^([A-Za-z0-9]\+@|https?|git|ssh|ftps?|rsync).*\.git/?$ ]]; then
    takegit "$1"
  else
    takedir "$@"
  fi
}

#
# Set variable "$1" to default value "$2" if "$1" is not yet defined.
#
# Arguments:
#    1. name - The variable to set
#    2. val  - The default value
# Return value:
#    0 if the variable exists, 3 if it was set
#
function default() {
    (( $+parameters[$1] )) && return 0
    typeset -g "$1"="$2"   && return 3
}

#
# Set environment variable "$1" to default value "$2" if "$1" is not yet defined.
#
# Arguments:
#    1. name - The env variable to set
#    2. val  - The default value
# Return value:
#    0 if the env variable exists, 3 if it was set
#
function env_default() {
    [[ ${parameters[$1]} = *-export* ]] && return 0
    export "$1=$2" && return 3
}


# Required for $langinfo
zmodload zsh/langinfo

# URL-encode a string
#
# Encodes a string using RFC 2396 URL-encoding (%-escaped).
# See: https://www.ietf.org/rfc/rfc2396.txt
#
# By default, reserved characters and unreserved "mark" characters are
# not escaped by this function. This allows the common usage of passing
# an entire URL in, and encoding just special characters in it, with
# the expectation that reserved and mark characters are used appropriately.
# The -r and -m options turn on escaping of the reserved and mark characters,
# respectively, which allows arbitrary strings to be fully escaped for
# embedding inside URLs, where reserved characters might be misinterpreted.
#
# Prints the encoded string on stdout.
# Returns nonzero if encoding failed.
#
# Usage:
#  xeta_urlencode [-r] [-m] [-P] <string> [<string> ...]
#
#    -r causes reserved characters (;/?:@&=+$,) to be escaped
#
#    -m causes "mark" characters (_.!~*''()-) to be escaped
#
#    -P causes spaces to be encoded as '%20' instead of '+'
function xeta_urlencode() {
  emulate -L zsh
  local -a opts
  zparseopts -D -E -a opts r m P

  local in_str="$@"
  local url_str=""
  local spaces_as_plus
  if [[ -z $opts[(r)-P] ]]; then spaces_as_plus=1; fi
  local str="$in_str"

  # URLs must use UTF-8 encoding; convert str to UTF-8 if required
  local encoding=$langinfo[CODESET]
  local safe_encodings
  safe_encodings=(UTF-8 utf8 US-ASCII)
  if [[ -z ${safe_encodings[(r)$encoding]} ]]; then
    str=$(echo -E "$str" | iconv -f $encoding -t UTF-8)
    if [[ $? != 0 ]]; then
      echo "Error converting string from $encoding to UTF-8" >&2
      return 1
    fi
  fi

  # Use LC_CTYPE=C to process text byte-by-byte
  local i byte ord LC_ALL=C
  export LC_ALL
  local reserved=';/?:@&=+$,'
  local mark='_.!~*''()-'
  local dont_escape="[A-Za-z0-9"
  if [[ -z $opts[(r)-r] ]]; then
    dont_escape+=$reserved
  fi
  # $mark must be last because of the "-"
  if [[ -z $opts[(r)-m] ]]; then
    dont_escape+=$mark
  fi
  dont_escape+="]"

  # Implemented to use a single printf call and avoid subshells in the loop,
  # for performance (primarily on Windows).
  local url_str=""
  for (( i = 1; i <= ${#str}; ++i )); do
    byte="$str[i]"
    if [[ "$byte" =~ "$dont_escape" ]]; then
      url_str+="$byte"
    else
      if [[ "$byte" == " " && -n $spaces_as_plus ]]; then
        url_str+="+"
      else
        ord=$(( [##16] #byte ))
        url_str+="%$ord"
      fi
    fi
  done
  echo -E "$url_str"
}

# URL-decode a string
#
# Decodes a RFC 2396 URL-encoded (%-escaped) string.
# This decodes the '+' and '%' escapes in the input string, and leaves
# other characters unchanged. Does not enforce that the input is a
# valid URL-encoded string. This is a convenience to allow callers to
# pass in a full URL or similar strings and decode them for human
# presentation.
#
# Outputs the encoded string on stdout.
# Returns nonzero if encoding failed.
#
# Usage:
#   xeta_urldecode <urlstring>  - prints decoded string followed by a newline
function xeta_urldecode {
  emulate -L zsh
  local encoded_url=$1

  # Work bytewise, since URLs escape UTF-8 octets
  local caller_encoding=$langinfo[CODESET]
  local LC_ALL=C
  export LC_ALL

  # Change + back to ' '
  local tmp=${encoded_url:gs/+/ /}
  # Protect other escapes to pass through the printf unchanged
  tmp=${tmp:gs/\\/\\\\/}
  # Handle %-escapes by turning them into `\xXX` printf escapes
  tmp=${tmp:gs/%/\\x/}
  local decoded="$(printf -- "$tmp")"

  # Now we have a UTF-8 encoded string in the variable. We need to re-encode
  # it if caller is in a non-UTF-8 locale.
  local -a safe_encodings
  safe_encodings=(UTF-8 utf8 US-ASCII)
  if [[ -z ${safe_encodings[(r)$caller_encoding]} ]]; then
    decoded=$(echo -E "$decoded" | iconv -f UTF-8 -t $caller_encoding)
    if [[ $? != 0 ]]; then
      echo "Error converting string from UTF-8 to $caller_encoding" >&2
      return 1
    fi
  fi

  echo -E "$decoded"
}

# Base64 encodes a string of text.
function encode64() {
    if [[ $# -eq 0 ]]; then
        cat | base64
    else
        printf '%s' $1 | base64
    fi
}

# Base64 encodes a file.
function encodefile64() {
    if [[ $# -eq 0 ]]; then
        echo "You must provide a filename"
    else
        base64 -i $1 -o $1.txt
        echo "${1}'s content encoded in base64 and saved as ${1}.txt"
    fi
}

# Decodes a string of text that has been encoded with base64.
function decode64() {
    if [[ $# -eq 0 ]]; then
        cat | base64 --decode
    else
        printf '%s' $1 | base64 --decode
    fi
}

#-------------------

# Copies the contents of a file to the system clipboard.
function copyfile {
    emulate -L zsh
    clipcopy $1
}

# Copies the absolute path of a file or directory to the system clipboard.
function copypath {
    local file="${1:-.}"
    [[ $file = /* ]] || file="$PWD/$file"
    # Copy the absolute path without resolving symlinks
    print -n "${file:a}" | clipcopy || return 1
    echo ${(%):-"%B${file:a}%b copied to clipboard."}
}

function which_dist() {
    if [ -f /etc/os-release ]; then
        # Read the contents of the os-release file
        source /etc/os-release
        if [[ $ID_LIKE == "debian" || $ID == "debian" ]]; then
            echo "Debian-based distribution"
        elif [[ $ID_LIKE == "ubuntu" || $ID == "ubuntu" ]]; then
            echo "Ubuntu distribution"
        elif [[ $ID_LIKE == "centos" || $ID == "centos" ]]; then
            echo "CentOS distribution"
        elif [[ $ID_LIKE == "fedora" || $ID == "fedora" ]]; then
            echo "Fedora distribution"
        elif [[ $ID_LIKE == "rhel" ||   $ID == "rhel" ]]; then
            echo "Red Hat Enterprise Linux (RHEL) distribution"
        else
            echo "Unknown distribution"
        fi
    else
        echo "Could not determine the distribution"
    fi
}

 
#-------------------
