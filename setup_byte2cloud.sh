#!/usr/bin/env bash
# =============================================================================
#  Byte2Cloud — Workshop Setup Script
#  Creates 25 team accounts + all task artifacts with correct permissions
#  Run as root:  sudo bash setup_byte2cloud.sh
# =============================================================================

set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Root check ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "This script must be run as root (sudo bash $0)"

# =============================================================================
#  CONFIGURATION — edit here if needed
# =============================================================================
TEAM_COUNT=25                       # number of teams
TEAM_PREFIX="team"                  # usernames: team01 … team25
DEFAULT_PASS="Byte2Cloud@2026"       # initial SSH password for all teams

MISSION_ROOT="/opt/mission"         # main mission directory (read-only to teams)
SECRETS_DIR="/var/mission/secrets"  # fragment 3 + 4 live here
SUBMIT_ROOT="/opt/submissions"      # teams upload answers here

# The secret message that gets base64-encoded and split into fragments
SECRET_MSG="BYTE2CLOUD MISSION COMPLETE — CODE WORD: PENGUINS FLY AT MIDNIGHT"

# A group that owns all immutable mission files
MISSION_GROUP="missionfiles"

# =============================================================================
#  STEP 0 — Pre-flight
# =============================================================================
info "Starting Byte2Cloud setup..."
info "Platform: $(uname -s) $(uname -r)"

# Detect distro for useradd vs adduser
if command -v adduser &>/dev/null && grep -qi debian /etc/os-release 2>/dev/null; then
    USE_ADDUSER=true
else
    USE_ADDUSER=false
fi

# =============================================================================
#  STEP 1 — Create the shared mission group
# =============================================================================
info "Creating mission group: ${MISSION_GROUP}"
if getent group "${MISSION_GROUP}" &>/dev/null; then
    warn "Group '${MISSION_GROUP}' already exists — skipping"
else
    groupadd "${MISSION_GROUP}"
    success "Group '${MISSION_GROUP}' created"
fi

# =============================================================================
#  STEP 2 — Create 25 team user accounts
# =============================================================================
info "Creating ${TEAM_COUNT} team accounts..."

CREATED=0; SKIPPED=0
for i in $(seq -w 1 "${TEAM_COUNT}"); do
    USERNAME="${TEAM_PREFIX}${i}"

    if id "${USERNAME}" &>/dev/null; then
        warn "User '${USERNAME}' already exists — skipping"
        ((SKIPPED++)) || true
        continue
    fi

    if $USE_ADDUSER; then
        adduser --disabled-password --gecos "Workshop Team ${i}" "${USERNAME}" &>/dev/null
        echo "${USERNAME}:${DEFAULT_PASS}" | chpasswd
    else
        useradd -m -c "Workshop Team ${i}" -s /bin/bash "${USERNAME}"
        echo "${USERNAME}:${DEFAULT_PASS}" | chpasswd
    fi

    ((CREATED++)) || true
done

success "Users created: ${CREATED}  |  Skipped (already exist): ${SKIPPED}"

# =============================================================================
#  STEP 3 — Build base64 fragments
# =============================================================================
info "Encoding secret message and splitting into 4 fragments..."

ENCODED=$(printf '%s' "${SECRET_MSG}" | base64 -w 0)
TOTAL_LEN=${#ENCODED}

# Split into 4 roughly equal chunks (portable — no bash substring required)
CHUNK=$(( TOTAL_LEN / 4 ))
PART1=$(printf '%s' "$ENCODED" | cut -c1-${CHUNK})
PART2=$(printf '%s' "$ENCODED" | cut -c$((CHUNK+1))-$((CHUNK*2)))
PART3=$(printf '%s' "$ENCODED" | cut -c$((CHUNK*2+1))-$((CHUNK*3)))
PART4=$(printf '%s' "$ENCODED" | cut -c$((CHUNK*3+1))-)   # remainder

success "Message encoded  (${TOTAL_LEN} base64 chars, ~${CHUNK} chars/fragment)"

# =============================================================================
#  STEP 4 — Create directory structure
# =============================================================================
info "Creating directory structure..."

# ── Main mission tree ─────────────────────────────────────────────────────────
#   /opt/mission/
#   ├── README.txt
#   ├── archives/2024/logs/          ← fragment_1.frag
#   └── hidden/                      ← .fragment_2.frag
#
#   /var/mission/secrets/            ← .fragment_3.frag  (readable by all)
#                                    ← .fragment_4.frag  (chmod 700 → needs sudo)
#
#   /opt/submissions/teamXX/         ← each team's writable upload folder

mkdir -p "${MISSION_ROOT}/archives/2024/logs"
mkdir -p "${MISSION_ROOT}/hidden"
mkdir -p "${SECRETS_DIR}"
mkdir -p "${SUBMIT_ROOT}"

# Explicitly set traverse permissions on every intermediate directory
# (mkdir -p inherits umask; we cannot rely on it for /var/mission)
chmod 755 /var/mission
chmod 755 "${SECRETS_DIR}"
chmod 755 "${MISSION_ROOT}"
chmod 755 "${MISSION_ROOT}/archives"
chmod 755 "${MISSION_ROOT}/archives/2024"
chmod 755 "${MISSION_ROOT}/archives/2024/logs"
chmod 755 "${MISSION_ROOT}/hidden"

success "Directories created"

# =============================================================================
#  STEP 5 — Write mission artifacts
# =============================================================================
info "Writing README.txt..."
cat > "${MISSION_ROOT}/README.txt" << 'EOF'
╔══════════════════════════════════════════════════════════╗
║              BYTE2CLOUD — MISSION BRIEF                  ║
╚══════════════════════════════════════════════════════════╝

A classified message has been fragmented and hidden across
this server. Your mission: find all 4 fragments, reassemble
them, decode the secret code word, and submit your answer.

FRAGMENT LOCATIONS
──────────────────
Fragment 1 — visible file
  /opt/mission/archives/2024/logs/fragment_1.frag
  → Navigate there and copy it to your local machine with SCP.

Fragment 2 — hidden file
  /opt/mission/hidden/.fragment_2.frag
  → Hidden files start with a dot. Use:  ls -la

Fragment 3 — hidden file in a different directory
  /var/mission/secrets/.fragment_3.frag
  → Same trick, different location.

Fragment 4 — locked (needs elevated privileges)
  /var/mission/secrets/.fragment_4.frag
  → Use:  sudo cat /var/mission/secrets/.fragment_4.frag

SCP FRAGMENTS 1-3 TO YOUR LOCAL MACHINE
────────────────────────────────────────
Change the paths with the actual path and run these on YOUR local machine (open a new terminal):

  mkdir ~/mission && cd ~/mission
  scp teamXX@<server>:/path/to/remote/fragment_1.frag .
  scp teamXX@<server>:/path/to/remote/.fragment_2.frag .
  scp teamXX@<server>:/path/to/remote/.fragment_3.frag .

FRAGMENT 4 — locked, cannot SCP directly
─────────────────────────────────────────
Fragment 4 is protected. Read it on the server using sudo,
then save it to your home directory first:

  (on the server)  sudo cat /var/mission/secrets/.fragment_4.frag > ~/fragment_4.frag

Then SCP it from your home directory:

  (on local)  scp teamXX@<server>:~/fragment_4.frag .

DECODING
────────
On your local machine (inside ~/mission/):

  cat fragment_1.frag .fragment_2.frag .fragment_3.frag fragment_4.frag > combined.b64
  base64 -d combined.b64 > message.txt
  cat message.txt

Find the CODE WORD in the message.

SUBMISSION
──────────
On your local machine:
  echo "CODE WORD: <your word>" > student-number.txt
  echo "Team: teamXX Student No : EC/XXXX/XX"          >> student-number.txt
  scp student-number.txt teamXX@<server>:submissions/

Good luck. The clock is ticking.
EOF

# ── Fragment 1 — openly named, visible with ls ────────────────────────────────
info "Writing fragment 1..."
printf '%s\n' "${PART1}" > "${MISSION_ROOT}/archives/2024/logs/fragment_1.frag"

# ── Fragment 2 — hidden file (dot prefix) ─────────────────────────────────────
info "Writing fragment 2 (hidden)..."
printf '%s\n' "${PART2}" > "${MISSION_ROOT}/hidden/.fragment_2.frag"

# ── Fragment 3 — different dir, hidden file ───────────────────────────────────
info "Writing fragment 3 (hidden, different dir)..."
printf '%s\n' "${PART3}" > "${SECRETS_DIR}/.fragment_3.frag"

# ── Fragment 4 — chmod 700, root-owned, requires sudo cat ────────────────────
info "Writing fragment 4 (chmod 700 — requires sudo)..."
printf '%s\n' "${PART4}" > "${SECRETS_DIR}/.fragment_4.frag"

success "All 4 fragments written"

# =============================================================================
#  STEP 6 — Permissions: lock down mission files (immutable to teams)
# =============================================================================
info "Setting ownership and permissions on mission files..."

# ── Ownership: root owns everything, missionfiles group for read access ───────
chown -R root:"${MISSION_GROUP}" "${MISSION_ROOT}"
chown -R root:"${MISSION_GROUP}" "${SECRETS_DIR}"

# ── Directories: root rwx, group r-x, others r-x ─────────────────────────────
#    Teams can cd into dirs and ls, but CANNOT create/delete/rename inside them
find "${MISSION_ROOT}" -type d -exec chmod 755 {} \;
find "${SECRETS_DIR}"  -type d -exec chmod 755 {} \;

# ── Fragment files: root rw-, group r--, others r--  (444) ───────────────────
#    Readable by everyone, writable/deletable ONLY by root
find "${MISSION_ROOT}" -type f -exec chmod 444 {} \;
find "${SECRETS_DIR}"  -type f -exec chmod 444 {} \;

# ── Fragment 4: chmod 700 — ONLY root can read it ────────────────────────────
chmod 700 "${SECRETS_DIR}/.fragment_4.frag"
chown root:root "${SECRETS_DIR}/.fragment_4.frag"

success "Fragment permissions set"
info "Fragment 4 is 700 (root only) — teams must use sudo to read it"

# ── Per-team submission directories + home symlink ────────────────────────────
#    Each team gets /opt/submissions/teamXX/ and ~/submissions -> that dir
info "Creating per-team submission directories..."
for i in $(seq -w 1 "${TEAM_COUNT}"); do
    USERNAME="${TEAM_PREFIX}${i}"
    SUBDIR="${SUBMIT_ROOT}/${USERNAME}"
    HOMEDIR="/home/${USERNAME}"

    mkdir -p "${SUBDIR}"
    chown "${USERNAME}:${USERNAME}" "${SUBDIR}"
    chmod 700 "${SUBDIR}"    # team owns it exclusively; others can't peek

    # Symlink ~/submissions -> /opt/submissions/teamXX/
    # so students can just:  scp file.txt teamXX@server:~/submissions/
    ln -sfn "${SUBDIR}" "${HOMEDIR}/submissions"
    chown -h "${USERNAME}:${USERNAME}" "${HOMEDIR}/submissions"
done

# The submissions root itself: root-owned, no write for others
chown root:root "${SUBMIT_ROOT}"
chmod 755 "${SUBMIT_ROOT}"

success "Submission directories created with ~/submissions symlink in each home dir"

# ── Add teams to mission group (so they can read group-owned files) ────────────
info "Adding all team users to '${MISSION_GROUP}' group..."
for i in $(seq -w 1 "${TEAM_COUNT}"); do
    usermod -aG "${MISSION_GROUP}" "${TEAM_PREFIX}${i}"
done
success "All team users added to '${MISSION_GROUP}'"

# =============================================================================
#  STEP 7 — Sudo rule for fragment 4 only (scoped, not full sudo)
# =============================================================================
info "Writing scoped sudo rule for fragment 4..."

SUDOERS_FILE="/etc/sudoers.d/workshop_byte2cloud"

cat > "${SUDOERS_FILE}" << EOF
# Workshop sudo rule — teams may ONLY sudo-read fragment 4
# Generated by setup_byte2cloud.sh
%${MISSION_GROUP} ALL=(root) NOPASSWD: /bin/cat ${SECRETS_DIR}/.fragment_4.frag
EOF

chmod 440 "${SUDOERS_FILE}"
visudo -cf "${SUDOERS_FILE}" && success "Sudoers rule validated and installed" \
    || { warn "visudo check failed — removing unsafe sudoers file"; rm "${SUDOERS_FILE}"; }

# =============================================================================
#  STEP 8 — Verify the full setup
# =============================================================================
info "Running verification checks..."
ERRORS=0

check() {
    local desc="$1"; local condition="$2"
    if eval "$condition" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC}  ${desc}"
    else
        echo -e "  ${RED}✗${NC}  ${desc}"
        ((ERRORS++))
    fi
}

check "Fragment 1 exists and is readable by all" \
    "[ -r '${MISSION_ROOT}/archives/2024/logs/fragment_1.frag' ]"

check "Fragment 2 is a hidden file" \
    "[ -f '${MISSION_ROOT}/hidden/.fragment_2.frag' ]"

check "Fragment 3 is a hidden file in /var/mission" \
    "[ -f '${SECRETS_DIR}/.fragment_3.frag' ]"

check "Fragment 4 has mode 700" \
    "[ \$(stat -c '%a' '${SECRETS_DIR}/.fragment_4.frag') = '700' ]"

check "README.txt exists" \
    "[ -f '${MISSION_ROOT}/README.txt' ]"

check "Submissions root exists" \
    "[ -d '${SUBMIT_ROOT}' ]"

check "team01 submission dir exists" \
    "[ -d '${SUBMIT_ROOT}/${TEAM_PREFIX}01' ]"

check "team01 ~/submissions symlink exists" \
    "[ -L '/home/${TEAM_PREFIX}01/submissions' ]"

check "Fragment files are NOT writable by group/other" \
    "! find '${MISSION_ROOT}' -type f -perm /0022 | grep -q ."

check "Sudoers rule installed" \
    "[ -f '${SUDOERS_FILE}' ]"

check "team01 is in missionfiles group" \
    "id ${TEAM_PREFIX}01 | grep -q '${MISSION_GROUP}'"

# ── Critical: test as actual team user, not root ──────────────────────────────
info "Verifying team user file visibility (running as team01)..."
CHECK_USER="${TEAM_PREFIX}01"
su - "${CHECK_USER}" -c "ls /opt/mission/README.txt"        &>/dev/null \
    && echo -e "  ${GREEN}✓${NC}  team01 can see README.txt" \
    || { echo -e "  ${RED}✗${NC}  team01 CANNOT see README.txt — permission problem!"; ((ERRORS++)) || true; }

su - "${CHECK_USER}" -c "ls /opt/mission/archives/2024/logs/fragment_1.frag" &>/dev/null \
    && echo -e "  ${GREEN}✓${NC}  team01 can see fragment_1.frag" \
    || { echo -e "  ${RED}✗${NC}  team01 CANNOT see fragment_1.frag"; ((ERRORS++)) || true; }

su - "${CHECK_USER}" -c "ls /var/mission/secrets/" &>/dev/null \
    && echo -e "  ${GREEN}✓${NC}  team01 can traverse /var/mission/secrets/" \
    || { echo -e "  ${RED}✗${NC}  team01 CANNOT traverse /var/mission/secrets/"; ((ERRORS++)) || true; }

su - "${CHECK_USER}" -c "cat /var/mission/secrets/.fragment_4.frag" &>/dev/null \
    && { echo -e "  ${RED}✗${NC}  team01 can read fragment_4 WITHOUT sudo — fix permissions!"; ((ERRORS++)) || true; } \
    || echo -e "  ${GREEN}✓${NC}  team01 correctly blocked from fragment_4 (needs sudo)"

echo ""
if [[ $ERRORS -eq 0 ]]; then
    success "All checks passed — server is ready!"
else
    warn "${ERRORS} check(s) failed — review output above"
fi

# =============================================================================
#  STEP 9 — Print summary
# =============================================================================
cat << EOF

${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}
${BOLD}   Byte2Cloud — Setup Complete${NC}
${BOLD}${CYAN}════════════════════════════════════════════════════════${NC}

  Teams          : team01 – team$(printf '%02d' ${TEAM_COUNT})
  SSH password   : ${DEFAULT_PASS}

  Fragment map
  ────────────
  [1]  ${MISSION_ROOT}/archives/2024/logs/fragment_1.frag  (444)
  [2]  ${MISSION_ROOT}/hidden/.fragment_2.frag              (444, hidden)
  [3]  ${SECRETS_DIR}/.fragment_3.frag                      (444, hidden)
  [4]  ${SECRETS_DIR}/.fragment_4.frag                      (700, sudo only)

  Sudo scope     : teams can ONLY sudo-cat fragment 4
                   (no other sudo access)

  Submissions    : ${SUBMIT_ROOT}/teamXX/   (each team owns their own)

${BOLD}  Share with students:${NC}
    ssh teamXX@$(hostname -I | awk '{print $1}')
    password: ${DEFAULT_PASS}

${BOLD}  To tear down after the workshop:${NC}
    sudo bash teardown_byte2cloud.sh

${CYAN}════════════════════════════════════════════════════════${NC}
EOF
