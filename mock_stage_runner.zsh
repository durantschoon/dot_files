#!/usr/bin/env zsh

# Clear old mock logs
rm -f logs/*

echo "Starting mock jobs..."

# Mock Job 1: db-migration (Runs smoothly)
(
    JOB="db-migration"
    echo "1. Started database backup" > "logs/${JOB}.outbox"
    sleep 2
    echo "1. Started database backup\n2. Backup complete, running schema migration" > "logs/${JOB}.outbox"
    sleep 3
    echo "1. Started database backup\n2. Backup complete, running schema migration\n3. Schema migration complete, building indices" > "logs/${JOB}.outbox"
    sleep 4
    echo "1. Started database backup\n2. Backup complete, running schema migration\n3. Schema migration complete, building indices\n4. DB Migration fully finished!" > "logs/${JOB}.outbox"
    echo "[$JOB] Finished smoothly."
) &

# Mock Job 2: frontend-setup (Hits a blocker)
(
    JOB="frontend-setup"
    echo "1. Cloned frontend repo" > "logs/${JOB}.outbox"
    sleep 2
    echo "1. Cloned frontend repo\n2. Installed node_modules" > "logs/${JOB}.outbox"
    sleep 2
    
    # Hit a blocker
    echo "[$JOB] Hitting a blocker..."
    echo "Should we use Tailwind or standard CSS for the styling?" > "logs/${JOB}.blocked"
    
    # Wait for inbox response
    echo "[$JOB] Waiting for input in logs/${JOB}.inbox..."
    while [[ ! -s "logs/${JOB}.inbox" ]]; do
        sleep 1
    done
    
    ANSWER=$(cat "logs/${JOB}.inbox")
    echo "[$JOB] Received answer: $ANSWER"
    
    # Clear the blocker
    rm -f "logs/${JOB}.blocked"
    
    # Resume work
    echo "1. Cloned frontend repo\n2. Installed node_modules\n3. Configured styling based on user answer: ${ANSWER}\n4. Finished frontend setup!" > "logs/${JOB}.outbox"
    echo "[$JOB] Finished after being unblocked."
) &

wait
echo "All mock jobs completed."
