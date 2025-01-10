#!/bin/bash

logger() {
    while read -r LINE
    do
        echo "[$(date +%T.%3N)]: $LINE"
    done
}

start_logging() {
    local file="$DTS_LOG_FILE"
    if [ -z "$LOGGING" ]; then
        LOGGING="true"
        if [ -z "$DESC" ]; then
            # Create file descriptor that echoes back anything written to it
            # and also logs that line to file with added timestamp prefix
            exec {DESC}> >(tee >(stdbuf -i0 -oL -eL ts "[%T]: " >> "$file"))
        fi
        exec 1>&$DESC
    fi
}

stop_logging() {
    if [ -n "$LOGGING" ]; then
        exec >&0
        LOGGING=
    fi
}

start_trace_logging() {
    local file="$DTS_VERBOSE_LOG_FILE"
    if [ -z "$BASH_XTRACEFD" ]; then
        exec {xtrace_fd}>>"$file"
        export BASH_XTRACEFD=${xtrace_fd}
        set -x
    fi
}

stop_trace_logging() {
    if [ -n "$BASH_XTRACEFD" ]; then
        set +x
        BASH_XTRACEFD=
    fi
}

export PS4="+[\$(date +%T.%3N)]:\${BASH_SOURCE[0]}:\${LINENO[0]}:\${FUNCNAME[0]:-main}: "
export LOGGING
export DESC
