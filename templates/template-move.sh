#!/bin/bash

# CUSTOMIZE: Change these to match your criteria
SOURCE_MAILBOX_FILTER="%INBOX%"                  # Source mailbox SQL filter
SENDER_FILTER="a.address = 'example@domain.com'" # Sender filter (can use = or LIKE)
SOURCE_MAILBOX="INBOX"                           # AppleScript source mailbox name
DESTINATION_MAILBOX="DestinationFolder"          # AppleScript destination mailbox name
ACCOUNT_NUMBER=1                                 # Mail.app account number (usually 1)

# Set to 1 to preview what would be moved without actually moving
DRY_RUN=0

# Check if Mail.app is still syncing
SYNC_COUNT=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "SELECT COUNT(*) FROM local_message_actions")
if [ "$SYNC_COUNT" -gt 0 ]; then
  echo "Mail.app is still syncing ($SYNC_COUNT pending actions)."
  echo "Please wait for sync to complete before running this script."
  echo "Check status: sqlite3 ~/Library/Mail/V10/MailData/Envelope\\ Index \"SELECT COUNT(*) FROM local_message_actions\""
  exit 1
fi

# Count total messages matching criteria before starting
echo "Checking for messages matching criteria..."
TOTAL_MESSAGES=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "SELECT COUNT(*)
   FROM messages m
   JOIN mailboxes mb ON m.mailbox = mb.ROWID
   JOIN addresses a ON m.sender = a.ROWID
   WHERE mb.url LIKE '$SOURCE_MAILBOX_FILTER'
   AND $SENDER_FILTER")

if [ "$TOTAL_MESSAGES" -eq 0 ]; then
  echo "No messages found matching criteria!"
  exit 0
fi

echo "Found $TOTAL_MESSAGES messages to move"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN MODE - No messages will be moved"
fi
echo "Starting move from $SOURCE_MAILBOX to $DESTINATION_MAILBOX..."
echo ""

TOTAL_MOVED=0
FAILED_COUNT=0

while true; do
  # Find messages matching criteria
  MESSAGE_IDS=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
    "SELECT m.ROWID
     FROM messages m
     JOIN mailboxes mb ON m.mailbox = mb.ROWID
     JOIN addresses a ON m.sender = a.ROWID
     WHERE mb.url LIKE '$SOURCE_MAILBOX_FILTER'
     AND $SENDER_FILTER
     LIMIT 50")

  if [ -z "$MESSAGE_IDS" ]; then
    echo ""
    echo "Done! Total moved: $TOTAL_MOVED messages"
    if [ "$FAILED_COUNT" -gt 0 ]; then
      echo "Failed to move: $FAILED_COUNT messages"
    fi
    exit 0
  fi

  # Convert to AppleScript list format
  IDS_ARRAY=$(echo "$MESSAGE_IDS" | tr '\n' ',' | sed 's/,$//')

  if [ "$DRY_RUN" -eq 1 ]; then
    # In dry run mode, just count what would be moved
    COUNT=$(echo "$MESSAGE_IDS" | wc -l | tr -d ' ')
    TOTAL_MOVED=$((TOTAL_MOVED + COUNT))
    echo "Would move $COUNT messages (Total: $TOTAL_MOVED)"
    sleep 0.1
  else
    # Move messages using AppleScript
    RESULT=$(osascript <<EOF
tell application "Mail"
  set messageIds to {$IDS_ARRAY}
  set moveCount to 0

  set acct to account $ACCOUNT_NUMBER
  set sourceBox to mailbox "$SOURCE_MAILBOX" of acct
  set destBox to mailbox "$DESTINATION_MAILBOX" of acct

  repeat with msgId in messageIds
    try
      set foundMessages to (every message of sourceBox whose id is msgId)
      if (count of foundMessages) > 0 then
        move (item 1 of foundMessages) to destBox
        set moveCount to moveCount + 1
      end if
    on error errMsg
      -- Message not found or could not be moved (likely already processed)
    end try
  end repeat

  return moveCount
end tell
EOF
    )

    # Check if AppleScript execution failed
    if [ $? -ne 0 ]; then
      echo "Error: AppleScript execution failed"
      FAILED_COUNT=$((FAILED_COUNT + 50))
    else
      TOTAL_MOVED=$((TOTAL_MOVED + RESULT))
      echo "Moved $RESULT messages (Total: $TOTAL_MOVED / $TOTAL_MESSAGES)"
    fi

    sleep 2
  fi
done
