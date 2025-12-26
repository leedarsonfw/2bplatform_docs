#!/bin/bash

# Periodic scheduler for sync_up.sh and sync_down.sh
# Runs sync script every 1 minute
# Usage: sync_scheduler.sh {start|stop|restart|status} [up|down]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_UP_SCRIPT="$SCRIPT_DIR/sync_up.sh"
SYNC_DOWN_SCRIPT="$SCRIPT_DIR/sync_down.sh"
INTERVAL=60

# Determine sync mode (up or down), default to up for backward compatibility
SYNC_MODE="${2:-up}"

if [ "$SYNC_MODE" != "up" ] && [ "$SYNC_MODE" != "down" ]; then
    echo "Error: Invalid sync mode: $SYNC_MODE (must be 'up' or 'down')"
    exit 1
fi

# Set script, PID file, and log file based on mode
if [ "$SYNC_MODE" = "up" ]; then
    SYNC_SCRIPT="$SYNC_UP_SCRIPT"
    PID_FILE="$SCRIPT_DIR/.sync_up_scheduler.pid"
    LOG_FILE="$SCRIPT_DIR/sync_up_scheduler.log"
    SCRIPT_NAME="sync_up.sh"
else
    SYNC_SCRIPT="$SYNC_DOWN_SCRIPT"
    PID_FILE="$SCRIPT_DIR/.sync_down_scheduler.pid"
    LOG_FILE="$SCRIPT_DIR/sync_down_scheduler.log"
    SCRIPT_NAME="sync_down.sh"
fi

# Function to log messages
log_message()
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if scheduler is already running
check_running()
{
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    return 1
}

# Function to run scheduler in background
run_scheduler()
{
    # Trap signals for graceful shutdown
    trap 'log_message "Scheduler stopped"; rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT

    # Main loop
    while true; do
        log_message "Executing $SCRIPT_NAME..."
        if bash "$SYNC_SCRIPT" >> "$LOG_FILE" 2>&1; then
            log_message "$SCRIPT_NAME completed successfully"
        else
            log_message "$SCRIPT_NAME failed with exit code $?"
        fi

        log_message "Waiting ${INTERVAL} seconds until next execution..."
        sleep "$INTERVAL"
    done
}

# Function to start scheduler
start_scheduler()
{
    if check_running; then
        echo "Scheduler is already running (PID: $(cat "$PID_FILE"))"
        exit 1
    fi

    if [ ! -f "$SYNC_SCRIPT" ]; then
        echo "Error: $SCRIPT_NAME not found at $SYNC_SCRIPT"
        exit 1
    fi

    if [ ! -x "$SYNC_SCRIPT" ]; then
        echo "Making $SCRIPT_NAME executable..."
        chmod +x "$SYNC_SCRIPT"
    fi

    # Remove previous log file if it exists
    if [ -f "$LOG_FILE" ]; then
        echo "Removing previous log file: $LOG_FILE"
        rm -f "$LOG_FILE"
    fi

    echo "Starting scheduler in background (interval: ${INTERVAL}s)"
    echo "Log file: $LOG_FILE"

    # Start scheduler in background
    (
        cd "$SCRIPT_DIR"
        run_scheduler
    ) > /dev/null 2>&1 &

    SCHEDULER_PID=$!
    echo "$SCHEDULER_PID" > "$PID_FILE"

    # Wait a moment to check if process started successfully
    sleep 1
    if ps -p "$SCHEDULER_PID" > /dev/null 2>&1; then
        echo "Scheduler started successfully (PID: $SCHEDULER_PID)"
        log_message "Scheduler started (PID: $SCHEDULER_PID)"
    else
        echo "Error: Failed to start scheduler"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# Function to stop scheduler
stop_scheduler()
{
    if ! check_running; then
        echo "Scheduler is not running"
        exit 1
    fi

    PID=$(cat "$PID_FILE")
    echo "Stopping scheduler (PID: $PID)"
    log_message "Stopping scheduler (PID: $PID)"
    kill "$PID" 2>/dev/null || true

    # Wait for process to stop
    for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Force killing scheduler (PID: $PID)"
        log_message "Force killing scheduler (PID: $PID)"
        kill -9 "$PID" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo "Scheduler stopped"
    log_message "Scheduler stopped"
}

# Function to show status
show_status()
{
    if check_running; then
        PID=$(cat "$PID_FILE")
        echo "Scheduler is running (PID: $PID)"
        ps -p "$PID" -o pid,etime,cmd 2>/dev/null || true
        echo ""
        echo "Recent log entries:"
        tail -n 5 "$LOG_FILE" 2>/dev/null || echo "No log file found"
    else
        echo "Scheduler is not running"
    fi
}

# Main command handling
case "${1:-}" in
    start)
        start_scheduler
        ;;
    stop)
        stop_scheduler
        ;;
    restart)
        stop_scheduler
        sleep 2
        start_scheduler
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status} [up|down]"
        echo ""
        echo "Commands:"
        echo "  start   - Start the scheduler"
        echo "  stop    - Stop the scheduler"
        echo "  restart - Restart the scheduler"
        echo "  status  - Show scheduler status"
        echo ""
        echo "Sync Mode (optional, default: up):"
        echo "  up      - Run sync_up.sh (sync to remote)"
        echo "  down    - Run sync_down.sh (sync from remote)"
        echo ""
        echo "Examples:"
        echo "  $0 start up    - Start scheduler for sync_up.sh"
        echo "  $0 start down  - Start scheduler for sync_down.sh"
        echo "  $0 stop up     - Stop scheduler for sync_up.sh"
        echo "  $0 status down - Show status for sync_down.sh"
        exit 1
        ;;
esac

