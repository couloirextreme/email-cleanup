#!/bin/bash

# CUSTOMIZE: Change these to match your criteria
MAILBOX_FILTER="%INBOX%"                        # Source mailbox (e.g., %INBOX%, %Sent%)
SENDER_FILTER="a.address LIKE '%example.com'"   # Sender filter (can use = or LIKE)
SUBJECT_FILTER="s.subject LIKE '%Newsletter%'"  # Subject filter (can use = or LIKE)
SOURCE_MAILBOX="INBOX"                          # AppleScript source mailbox name
TRASH_MAILBOX="Deleted Messages"                # AppleScript trash mailbox name
ACCOUNT_NUMBER=1                                # Mail.app account number (usually 1)

# Set to 1 to enable subject filtering, 0 to disable
USE_SUBJECT_FILTER=0

# Set to 1 to preview what would be deleted without actually deleting
DRY_RUN=0

# Check if Mail.app is still syncing
SYNC_COUNT=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index "SELECT COUNT(*) FROM local_message_actions")
if [ "$SYNC_COUNT" -gt 0 ]; then
  echo "Mail.app is still syncing ($SYNC_COUNT pending actions)."
  echo "Please wait for sync to complete before running this script."
  echo "Check status: sqlite3 ~/Library/Mail/V10/MailData/Envelope\\ Index \"SELECT COUNT(*) FROM local_message_actions\""
  exit 1
fi

# Build WHERE clause based on filters enabled
if [ "$USE_SUBJECT_FILTER" -eq 1 ]; then
  SUBJECT_JOIN="JOIN subjects s ON m.subject = s.ROWID"
  SUBJECT_WHERE="AND $SUBJECT_FILTER"
else
  SUBJECT_JOIN=""
  SUBJECT_WHERE=""
fi

# Count total messages matching criteria before starting
echo "Checking for messages matching criteria..."
TOTAL_MESSAGES=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "SELECT COUNT(*)
   FROM messages m
   JOIN mailboxes mb ON m.mailbox = mb.ROWID
   JOIN addresses a ON m.sender = a.ROWID
   $SUBJECT_JOIN
   WHERE mb.url LIKE '$MAILBOX_FILTER'
   AND $SENDER_FILTER
   $SUBJECT_WHERE")

if [ "$TOTAL_MESSAGES" -eq 0 ]; then
  echo "No messages found matching criteria!"
  exit 0
fi

echo "Found $TOTAL_MESSAGES messages to delete"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN MODE - No messages will be deleted"
fi
echo "Starting cleanup..."
echo ""

TOTAL_DELETED=0
FAILED_COUNT=0

while true; do
  # Find messages matching criteria
  MESSAGE_IDS=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
    "SELECT m.ROWID
     FROM messages m
     JOIN mailboxes mb ON m.mailbox = mb.ROWID
     JOIN addresses a ON m.sender = a.ROWID
     $SUBJECT_JOIN
     WHERE mb.url LIKE '$MAILBOX_FILTER'
     AND $SENDER_FILTER
     $SUBJECT_WHERE
     LIMIT 50")

  if [ -z "$MESSAGE_IDS" ]; then
    echo ""
    echo "Done! Total deleted: $TOTAL_DELETED messages"
    if [ "$FAILED_COUNT" -gt 0 ]; then
      echo "Failed to delete: $FAILED_COUNT messages"
    fi
    exit 0
  fi

  # Convert to AppleScript list format
  IDS_ARRAY=$(echo "$MESSAGE_IDS" | tr '\n' ',' | sed 's/,$//')

  if [ "$DRY_RUN" -eq 1 ]; then
    # In dry run mode, just count what would be deleted
    COUNT=$(echo "$MESSAGE_IDS" | wc -l | tr -d ' ')
    TOTAL_DELETED=$((TOTAL_DELETED + COUNT))
    echo "Would delete $COUNT messages (Total: $TOTAL_DELETED)"
    sleep 0.1
  else
    # Delete messages using AppleScript
    RESULT=$(osascript <<EOF
tell application "Mail"
  set messageIds to {$IDS_ARRAY}
  set deleteCount to 0

  set acct to account $ACCOUNT_NUMBER
  set sourceBox to mailbox "$SOURCE_MAILBOX" of acct
  set trashBox to mailbox "$TRASH_MAILBOX" of acct

  repeat with msgId in messageIds
    try
      set foundMessages to (every message of sourceBox whose id is msgId)
      if (count of foundMessages) > 0 then
        move (item 1 of foundMessages) to trashBox
        set deleteCount to deleteCount + 1
      end if
    on error errMsg
      -- Message not found or could not be moved (likely already processed)
    end try
  end repeat

  return deleteCount
end tell
EOF
    )

    # Check if AppleScript execution failed
    if [ $? -ne 0 ]; then
      echo "Error: AppleScript execution failed"
      FAILED_COUNT=$((FAILED_COUNT + 50))
    else
      TOTAL_DELETED=$((TOTAL_DELETED + RESULT))
      echo "Deleted $RESULT messages (Total: $TOTAL_DELETED / $TOTAL_MESSAGES)"
    fi

    sleep 2
  fi
done
