#!/bin/bash
#
# Copyright (c) 2010 Linagora
# Patrick Guiran <pguiran@linagora.com>
# http://github.com/Tauop/sshGate
#
# sshGate is free software, you can redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License, or (at your option) any later version.
#
# sshGate is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

if [ $# -ne 1 ]; then
  echo "your SSH KEY is not well configured. Please contact the sshGate administrator."
  exit 1
fi

# GLOBAL configuration -------------------------------------------------------
SSHKEY_USER=$1
SFTP_SERVER=/usr/libexec/openssh/sftp-server

# %% __SSHGATE_CONF__ %% <-- WARNING: don't remove. used by install.sh
if [ -z "${__SSHGATE_CONF__}" ]; then
  [ -r "${0%/*}/sshgate.conf" ] && . ${0%/*}/sshgate.conf
  [ -r "`pwd`/sshgate.conf"   ] && . `pwd`/sshgate.conf
  if [ -z "${__SSHGATE_CONF__:-}" ]; then
    echo "ERROR: Unable to load sshgate.conf"
    exit 1;
  fi
fi

# %% __SSHGATE_FUNC__ %% <-- WARNING: don't remove. used by install.sh
if [ -z "${__SSHGATE_FUNC__}" ]; then
  [ -r "${0%/*}/sshgate.func" ] && . ${0%/*}/sshgate.func
  [ -r "`pwd`/sshgate.func"   ] && . `pwd`/sshgate.func
  if [ -z "${__SSHGATE_FUNC__:-}" ]; then
    echo "ERROR: Unable to load sshgate.func"
    exit 1;
  fi
fi


# one little function
LOG () { local file=$1; shift; echo "$(date +'[%D %T]') $*" >> ${file}; }

if [ -z ${SSHKEY_USER:-} ]; then
  echo "your SSH key is not well configured. Please, contact the sshGate administrator."
  exit 1
fi


# determine action type (ssh or scp) and build TARGET_HOST -------------------
do_ssh='false'

if [ "${SSH_ORIGINAL_COMMAND}" != "${SSH_ORIGINAL_COMMAND#${SFTP_SERVER} }" \
  -o "${SSH_ORIGINAL_COMMAND}" != "${SSH_ORIGINAL_COMMAND#scp }" ]; then
  # SSH_ORIGNAL_COMMAND ends with the name of the target host
  TARGET_HOST=${SSH_ORIGINAL_COMMAND##* }

  if [ "${TARGET_HOST%%/*}" != "${TARGET_HOST}" ]; then
    SSH_ORIGINAL_COMMAND=${SSH_ORIGINAL_COMMAND%% ${TARGET_HOST}}
    target_files=${TARGET_HOST#*/}
    TARGET_HOST=${TARGET_HOST%%/*}
    if [ -z "${target_files}" -o "${target_files#/}" = "${target_files}" ]; then
      target_files="~/${target_files}"
    fi
    SSH_ORIGINAL_COMMAND="${SSH_ORIGINAL_COMMAND} ${target_files}"
  else
    SSH_ORIGINAL_COMMAND=${SSH_ORIGINAL_COMMAND%% ${TARGET_HOST}}
    SSH_ORIGINAL_COMMAND="${SSH_ORIGINAL_COMMAND} ${TARGET_SCP_DIR}"
  fi
else
  # SSH_ORIGINAL_COMMAND contain the name of the target host
  TARGET_HOST=${SSH_ORIGINAL_COMMAND%% *}
  do_ssh='true'
fi

# public commands ------------------------------------------------------------
if [ "${do_ssh}" = 'true' -a "${TARGET_HOST}" = 'cmd' ]; then
  # inpired from ScriptHelper/cli.lib.sh
  BUILD_SED_CODE () {
    local sed_cmd=
    for word in $( echo "$1" | tr ' ' $'\n' ); do
      [ "${word}" = '?' ] && word="\([^ ]*\)"
      sed_cmd="${sed_cmd} *${word}"
    done
    echo -n "s/^${sed_cmd} *$/$2/p; t;"
  }
  code=
  code="${code} $(BUILD_SED_CODE 'cmd list targets'   'USER_LIST_TARGETS')"
  code="${code} $(BUILD_SED_CODE 'cmd list targets ?' 'USER_LIST_TARGETS \1')"
  code="${code} $(BUILD_SED_CODE 'cmd sshkey all'     'DISPLAY_USER_SSHKEY all')"
  code="${code} $(BUILD_SED_CODE 'cmd sshkey ?'       'DISPLAY_USER_SSHKEY \1')"
  code="${code} a echo 'ERROR: unknown command' "
  eval $(echo "${SSH_ORIGINAL_COMMAND}" | sed -n -e "$code" )
  exit 0;
fi

# Determine information for connecting to the host ---------------------------
TARGET_USER=${SSHGATE_TARGETS_DEFAULT_USER}
TARGET_HOST=$( TARGET_REAL "${TARGET_HOST}" )
GLOG_FILE=$( TARGET_LOG_FILE )

TARGET_SSHKEY=$( TARGET_PRIVATE_SSHKEY )
if [ -z "${TARGET_SSHKEY}" -o ! -r "${TARGET_SSHKEY:-}" ]; then
  echo "ERROR: can't read target host ssh key. Please contact the sshGate administrator"
  exit 1
fi

# check ACL ------------------------------------------------------------------
if [ $( HAS_ACCESS ) = 'false' ]; then
  echo "ERROR: The ${TARGET_HOST} doesn't exist or you don't have access to it"
  exit 1
fi

# Do the stuff ;-) -----------------------------------------------------------
LOG ${GLOG_FILE} "New session $$. Connection from ${SSH_CONNECTION%% *} with SSH_ORIGINAL_COMMAND = ${SSH_ORIGINAL_COMMAND:-}"
if [ "${do_ssh:-}" = 'true' ]; then
  SLOG_FILE=$( TARGET_SESSION_LOG_FILE )
  LOG ${GLOG_FILE} "Creating session log file ${SLOG_FILE}"
  LOG ${SSHGATE_LOG_FILE} "[SSSH] ${SSHKEY_USER} -> ${TARGET_USER}@${TARGET_HOST}"

  ssh -i ${TARGET_SSHKEY} ${TARGET_USER}@${TARGET_HOST} | tee ${SLOG_FILE}
  LOG ${GLOG_FILE} "Session $$ ended. logfile = ${SLOG_FILE}"
else
  LOG ${SSHGATE_LOG_FILE} "[SCP] ${SSHKEY_USER} -> ${TARGET_USER}@${TARGET_HOST} ${SSH_ORIGINAL_COMMAND}"

  ssh -i ${TARGET_SSHKEY} ${TARGET_USER}@${TARGET_HOST} ${SSH_ORIGINAL_COMMAND}
  LOG ${GLOG_FILE} "Transfert $$ completed."
fi

exit ${RETURN_VALUE}