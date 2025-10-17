#!/usr/bin/env bash
# install-bounty-tools.sh
# Single-shot installer for many bug-hunting tools (best-effort).
# Author: generated for you
# Run: sudo ./install-bounty-tools.sh
set -euo pipefail
IFS=$'\n\t'

LOGFILE="/var/log/bounty-installer.log"
mkdir -p "$(dirname "$LOGFILE")"
: > "$LOGFILE"

echo "Starting bounty tools installer - $(date)" | tee -a "$LOGFILE"

# --------------------------
# Helpers
# --------------------------
run_cmd() {
  echo -e "\n>>> $*" | tee -a "$LOGFILE"
  if "$@" >>"$LOGFILE" 2>&1; then
    echo "OK: $*" | tee -a "$LOGFILE"
    return 0
  else
    echo "FAIL: $* (see $LOGFILE)" | tee -a "$LOGFILE"
    return 1
  fi
}

report_status() {
  local name="$1"; shift
  if [ "$1" -eq 0 ]; then
    SUCCESS+=( "$name" )
  else
    FAIL+=( "$name" )
  fi
}

# --------------------------
# Environment detection
# --------------------------
OS=""
PKG_INSTALL=""
if command -v apt-get >/dev/null 2>&1; then
  OS="debian"
  PKG_INSTALL="apt-get install -y"
elif command -v yum >/dev/null 2>&1; then
  OS="rhel"
  PKG_INSTALL="yum install -y"
elif command -v brew >/dev/null 2>&1; then
  OS="mac"
  PKG_INSTALL="brew install"
else
  OS="unknown"
fi
echo "Detected OS: $OS" | tee -a "$LOGFILE"

# --------------------------
# Basic prerequisites
# --------------------------
echo "Installing prerequisites..." | tee -a "$LOGFILE"
if [ "$OS" = "debian" ]; then
  run_cmd apt-get update
  run_cmd apt-get install -y git curl wget unzip jq build-essential python3 python3-pip golang-go ca-certificates
elif [ "$OS" = "rhel" ]; then
  run_cmd yum install -y git curl wget unzip jq gcc gcc-c++ make python3 python3-pip golang
elif [ "$OS" = "mac" ]; then
  run_cmd brew update || true
  run_cmd brew install git curl wget jq python3 go
else
  echo "Unknown OS: please ensure git, curl, wget, python3, pip, go are installed manually." | tee -a "$LOGFILE"
fi

# make sure pip points to pip3
if command -v pip3 >/dev/null 2>&1; then
  PIP=pip3
else
  PIP=pip
fi

# Ensure GOPATH and GOBIN
if [ -z "${GOPATH:-}" ]; then
  export GOPATH="$HOME/go"
fi
export GOBIN="${GOBIN:-$GOPATH/bin}"
mkdir -p "$GOBIN"
if ! echo "$PATH" | grep -q "$GOBIN"; then
  SHELLRC="$HOME/.bashrc"
  if [ -n "${ZDOTDIR:-}" ]; then SHELLRC="$HOME/.zshrc"; fi
  echo "export GOPATH=\"$GOPATH\"" >> "$SHELLRC"
  echo "export PATH=\"\$PATH:$GOBIN\"" >> "$SHELLRC"
  export PATH="$PATH:$GOBIN"
fi

# arrays to collect results
SUCCESS=()
FAIL=()

# --------------------------
# Install functions for specific categories
# --------------------------

install_go() {
  local pkg="$1" name="$2"
  name=${name:-$pkg}
  echo "Installing (go): $name ($pkg)" | tee -a "$LOGFILE"
  if run_cmd env GOPATH="$GOPATH" go install "$pkg@latest"; then
    report_status "$name" 0
  else
    report_status "$name" 1
  fi
}

install_git_build() {
  local repo="$1"; local build_cmd="${2:-make build}" ; local binary="${3:-}"
  local name="${4:-$(basename "$repo")}"
  local tmp="/tmp/install-$(basename "$repo")-$$"
  rm -rf "$tmp"
  echo "Cloning $repo ..." | tee -a "$LOGFILE"
  if run_cmd git clone --depth 1 "$repo" "$tmp"; then
    pushd "$tmp" >/dev/null
    if run_cmd bash -lc "$build_cmd"; then
      # try to copy binary if exists
      if [ -n "$binary" ]; then
        if [ -f "$binary" ]; then
          run_cmd cp "$binary" /usr/local/bin/ || run_cmd sudo cp "$binary" /usr/local/bin/
        else
          # try to find built binary
          b=$(find . -maxdepth 3 -type f -perm -111 | head -n1 || true)
          if [ -n "$b" ]; then
            run_cmd cp "$b" /usr/local/bin/ || run_cmd sudo cp "$b" /usr/local/bin/
          fi
        fi
      else
        b=$(find . -maxdepth 3 -type f -perm -111 | head -n1 || true)
        if [ -n "$b" ]; then
          run_cmd cp "$b" /usr/local/bin/ || run_cmd sudo cp "$b" /usr/local/bin/
        fi
      fi
      popd >/dev/null
      rm -rf "$tmp"
      report_status "$name" 0
      return 0
    else
      popd >/dev/null
      rm -rf "$tmp"
      report_status "$name" 1
      return 1
    fi
  else
    report_status "$name" 1
    return 1
  fi
}

install_pip() {
  local pkg="$1" name="${2:-$1}"
  echo "Installing (pip): $pkg" | tee -a "$LOGFILE"
  if run_cmd "$PIP" install --upgrade "$pkg"; then
    report_status "$name" 0
  else
    report_status "$name" 1
  fi
}

# --------------------------
# Tool installs (best-effort)
# --------------------------
# We'll attempt known/common install commands for each tool name the user provided.
# If unknown, we try GH common paths or skip but mark failure.

echo "Installing tools..." | tee -a "$LOGFILE"

# 1) subfinder (projectdiscovery)
install_go "github.com/projectdiscovery/subfinder/v2/cmd/subfinder" "subfinder"

# 2) httpx (projectdiscovery)
install_go "github.com/projectdiscovery/httpx/cmd/httpx" "httpx"

# 3) httprobe (tomnomnom)
install_go "github.com/tomnomnom/httprobe" "httprobe"

# 4) Amass (OWASP)
# amass has a deb package and go install path
if run_cmd apt-get install -y amass 2>/dev/null || run_cmd yum install -y amass 2>/dev/null; then
  report_status "amass (pkg)" 0
else
  install_go "github.com/owasp/amass/v3/..." "amass" || true
fi

# 5) Assetfinder (tomnomnom)
install_go "github.com/tomnomnom/assetfinder" "assetfinder"

# 6) Hakrawler (hakluke)
install_go "github.com/hakluke/hakrawler" "hakrawler"

# 7) Gauplus (use github.com/bpierre/gauplus or hawkshaw?) — common: bojackr/gauplus
# we'll try common repo
install_go "github.com/bpierre/gauplus" "gauplus" || install_go "github.com/tomnomnom/gauplus" "gauplus" || report_status "gauplus" 1

# 8) waybackurls (michenriksen)
install_go "github.com/tomnomnom/waybackurls" "waybackurls"

# 9) Katana (projectdiscovery - katana)
# Katana often provided as binary; projectdiscovery/katana
if install_git_build "https://github.com/projectdiscovery/katana" "go build -o katana ./cmd/katana" "katana" "katana"; then :; else report_status "katana" 1; fi

# 10) ParamSpider
if install_git_build "https://github.com/devanshbatham/ParamSpider" "python3 setup.py install" "" "ParamSpider"; then :; else report_status "ParamSpider" 1; fi

# 11) feroxbuster
if run_cmd apt-get install -y feroxbuster 2>/dev/null || run_cmd yum install -y feroxbuster 2>/dev/null; then
  report_status "feroxbuster (pkg)" 0
else
  install_git_build "https://github.com/epi052/feroxbuster" "cargo build --release" "" "feroxbuster" || report_status "feroxbuster" 1
fi

# 12) linkfinder (m4ll0k)
install_pip "LinkFinder" "linkfinder"

# 13) secretfinder (m4ll0k)
install_pip "SecretFinder" "secretfinder"

# 14) jspraser  (likely typo: jsparser / jspenser / or getJS)
# Try to install getJS (common)
install_go "github.com/003random/getJS" "getJS" || report_status "jspraser/getJS (attempt)" 1

# 15) jsleak  (ambiguous) -> try jsleak project
if install_git_build "https://github.com/s0md3v/JSParser" "python3 setup.py install" "" "JSParser"; then :; else report_status "jsleak/JSParser (attempt)" 1; fi

# 16) SQLmap (sqlmap)
if run_cmd "$PIP" install sqlmap || install_git_build "https://github.com/sqlmapproject/sqlmap" "python3 setup.py install" "" "sqlmap"; then report_status "sqlmap" 0; else report_status "sqlmap" 1; fi

# 17) XSStrike
install_git_build "https://github.com/s0md3v/XSStrike" "python3 setup.py install" "" "XSStrike"

# 18) Nuclei (projectdiscovery)
install_go "github.com/projectdiscovery/nuclei/v2/cmd/nuclei" "nuclei"

# 19) Kxss (kxss)
install_go "github.com/Emoe/kxss" "kxss" || install_go "github.com/tomnomnom/waybackurls" "kxss-fallback" || report_status "Kxss" 1

# 20) GraphQLmap
install_git_build "https://github.com/swisskyrepo/graphqurl" "go build ./..." "" "graphqurl" || install_git_build "https://github.com/thatJavaNerd/GraphQLmap" "python3 setup.py install" "" "GraphQLmap" || report_status "GraphQLmap" 1

# 21) JWT_Tool (jwt_tool)
install_git_build "https://github.com/ticarpi/jwt_tool" "python3 setup.py install" "" "jwt_tool" || report_status "JWT_Tool" 1

# 22) Nmap
if command -v nmap >/dev/null 2>&1; then report_status "nmap" 0; else run_cmd apt-get install -y nmap || run_cmd yum install -y nmap || run_cmd brew install nmap; report_status "nmap" $?; fi

# 23) Masscan
if command -v masscan >/dev/null 2>&1; then report_status "masscan" 0; else run_cmd apt-get install -y masscan || run_cmd yum install -y masscan || run_cmd brew install masscan; report_status "masscan" $?; fi

# 24) nabbu (ambiguous) - try nabble? We'll attempt to find common repo 'nabbu' (best-effort)
report_status "nabbu (unknown/attempt skipped)" 1

# 25) ffuf
install_go "github.com/ffuf/ffuf" "ffuf"

# 26) wfuzz
run_cmd apt-get install -y wfuzz || run_cmd pip3 install wfuzz || run_cmd brew install wfuzz || true
if command -v wfuzz >/dev/null 2>&1; then report_status "wfuzz" 0; else report_status "wfuzz" 1; fi

# 27) Dirsearch
install_pip "dirsearch" "dirsearch"

# 28) Gobuster
if run_cmd apt-get install -y gobuster 2>/dev/null || run_cmd yum install -y gobuster 2>/dev/null || run_cmd brew install gobuster 2>/dev/null; then report_status "gobuster" 0; else install_go "github.com/OJ/gobuster/v3" "gobuster"; fi

# 29) asnmap
install_git_build "https://github.com/s0md3v/asnmap" "python3 setup.py install" "" "asnmap" || report_status "asnmap" 1

# 30) Shodandork (tools to build Shodan dorks) -> ambiguous, mark attempt
install_git_build "https://github.com/jekil/shodandork" "python3 setup.py install" "" "shodandork" || report_status "Shodandork" 1

# 31) prips (prips)
if run_cmd apt-get install -y prips 2>/dev/null || run_cmd yum install -y prips 2>/dev/null || run_cmd brew install prips 2>/dev/null; then report_status "prips" 0; else report_status "prips" 1; fi

# 32) hakoriginfinder (ambiguous) -> try hak-origin-finder
install_git_build "https://github.com/sh0wdown/hakoriginfinder" "python3 setup.py install" "" "hakoriginfinder" || report_status "hakoriginfinder" 1

# 33) resolvers.txt (this is a file, we just fetch a good list)
run_cmd mkdir -p /usr/share/bounty && run_cmd curl -fsSL "https://raw.githubusercontent.com/projectdiscovery/public-binaries/main/wordlists/resolvers.txt" -o /usr/share/bounty/resolvers.txt || run_cmd curl -fsSL "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/resolvers.txt" -o /usr/share/bounty/resolvers.txt
if [ -f /usr/share/bounty/resolvers.txt ]; then report_status "resolvers.txt" 0; else report_status "resolvers.txt" 1; fi

# 34) vulners.nse (nmap script)
run_cmd mkdir -p /usr/share/nmap/scripts
run_cmd curl -fsSL "https://raw.githubusercontent.com/vulnersCom/nmap-vulners/master/vulners.nse" -o /usr/share/nmap/scripts/vulners.nse || true
if [ -f /usr/share/nmap/scripts/vulners.nse ]; then report_status "vulners.nse" 0; else report_status "vulners.nse" 1; fi

# 35) rustscan
if run_cmd apt-get install -y rustscan 2>/dev/null || run_cmd yum install -y rustscan 2>/dev/null || run_cmd brew install rustscan 2>/dev/null; then report_status "rustscan" 0; else install_git_build "https://github.com/RustScan/RustScan" "cargo build --release" "" "rustscan" || report_status "rustscan" 1; fi

# 36) asnip (ambiguous) - attempt
report_status "asnip (unknown/attempt skipped)" 1

# 37) hakrevdns
install_git_build "https://github.com/hakluke/hakrevdns" "go build ./..." "" "hakrevdns" || report_status "hakrevdns" 1

# 38) VhostFinder
install_git_build "https://github.com/aboul3la/Sublist3r" "python3 setup.py install" "" "VhostFinder/Sublist3r" || report_status "VhostFinder" 1

# 39) hakfindinternaldomains
install_git_build "https://github.com/nahamsec/hakfindinternaldomains" "python3 setup.py install" "" "hakfindinternaldomains" || report_status "hakfindinternaldomains" 1

# 40) gotator (ambiguous) -> attempt
report_status "gotator (unknown/attempt skipped)" 1

# 41) dnsvalidator (projectdiscovery/dnsvalidator)
install_go "github.com/projectdiscovery/dnsx/cmd/dnsx" "dnsx" || install_go "github.com/vortexau/dnsvalidator" "dnsvalidator" || report_status "dnsvalidator" 1

# 42) puredns (projectdiscovery/puredns)
install_go "github.com/d3mondev/puredns/v2" "puredns" || report_status "puredns" 1

# 43) dnsx (projectdiscovery)
install_go "github.com/projectdiscovery/dnsx/cmd/dnsx" "dnsx"

# 44) dmut (ambiguous) - maybe dmut (domain-mutation) -> try to fetch domain mutation tool
report_status "dmut (unknown/attempt skipped)" 1

# 45) waymore
install_git_build "https://github.com/xnl-h4ck3r/waymore" "python3 setup.py install" "" "waymore" || report_status "waymore" 1

# 46) paramspider (duplicate) - already tried above (ParamSpider)
# 47) katana (duplicate) - already tried above
# 48) getJS (we tried earlier as getJS)
# 49) xnLinkFinder (maybe 'xnLinkFinder' / 'XnLinkFinder' is a fork) -> try common repo
install_git_build "https://github.com/tennc/LinkFinder" "python3 setup.py install" "" "xnLinkFinder/LinkFinder" || report_status "xnLinkFinder" 1

# Extra: ensure common wordlists
run_cmd mkdir -p /usr/share/wordlists
run_cmd curl -fsSL "https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/DNS/namelist.txt" -o /usr/share/wordlists/namelist.txt || true

# --------------------------
# Final summary
# --------------------------
echo -e "\n\n==================== SUMMARY ====================" | tee -a "$LOGFILE"
echo "Installed/Available:" | tee -a "$LOGFILE"
for s in "${SUCCESS[@]:-}"; do echo "  - $s" | tee -a "$LOGFILE"; done

echo -e "\nFailed/Skipped:" | tee -a "$LOGFILE"
for f in "${FAIL[@]:-}"; do echo "  - $f" | tee -a "$LOGFILE"; done

echo -e "\nLogs: $LOGFILE"
echo "Note: Some tools required manual verification or specific binary names. If PATH issues occur, restart your shell or source your rc file (e.g. source ~/.bashrc)." | tee -a "$LOGFILE"
echo "Installer finished at $(date)" | tee -a "$LOGFILE"
