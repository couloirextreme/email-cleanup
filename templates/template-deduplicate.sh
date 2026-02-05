#!/bin/bash

# CUSTOMIZE: Change these to match your target mailbox
MAILBOX_FILTER="%INBOX%"           # SQL LIKE pattern (e.g., %INBOX%, %Sent%, %FolderName%)
SOURCE_MAILBOX="INBOX"             # AppleScript mailbox name
TRASH_MAILBOX="Deleted Messages"   # AppleScript trash mailbox name
ACCOUNT_NUMBER=1                   # Mail.app account number (usually 1)

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

# Count total duplicates before starting
echo "Checking for duplicates in $SOURCE_MAILBOX..."
TOTAL_DUPES=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
  "SELECT COUNT(*) FROM messages m
   JOIN mailboxes mb ON m.mailbox = mb.ROWID
   WHERE mb.url LIKE '$MAILBOX_FILTER'
   AND m.global_message_id IN (
     SELECT global_message_id FROM messages m2
     JOIN mailboxes mb2 ON m2.mailbox = mb2.ROWID
     WHERE mb2.url LIKE '$MAILBOX_FILTER'
     GROUP BY global_message_id
     HAVING COUNT(*) > 1
   )
   AND m.ROWID NOT IN (
     SELECT MIN(m3.ROWID) FROM messages m3
     JOIN mailboxes mb3 ON m3.mailbox = mb3.ROWID
     WHERE mb3.url LIKE '$MAILBOX_FILTER'
     GROUP BY m3.global_message_id
   )")

if [ "$TOTAL_DUPES" -eq 0 ]; then
  echo "No duplicates found!"
  exit 0
fi

echo "Found $TOTAL_DUPES duplicate messages to process"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY RUN MODE - No messages will be deleted"
fi
echo "Starting cleanup..."
echo ""

TOTAL_DELETED=0
FAILED_COUNT=0

while true; do
  # Find duplicate messages in the target mailbox
  # Keeps the message with lowest ROWID (oldest), deletes the rest
  MESSAGE_IDS=$(sqlite3 ~/Library/Mail/V10/MailData/Envelope\ Index \
    "SELECT m.ROWID FROM messages m
     JOIN mailboxes mb ON m.mailbox = mb.ROWID
     WHERE mb.url LIKE '$MAILBOX_FILTER'
     AND m.global_message_id IN (
       SELECT global_message_id FROM messages m2
       JOIN mailboxes mb2 ON m2.mailbox = mb2.ROWID
       WHERE mb2.url LIKE '$MAILBOX_FILTER'
       GROUP BY global_message_id
       HAVING COUNT(*) > 1
     )
     AND m.ROWID NOT IN (
       SELECT MIN(m3.ROWID) FROM messages m3
       JOIN mailboxes mb3 ON m3.mailbox = mb3.ROWID
       WHERE mb3.url LIKE '$MAILBOX_FILTER'
       GROUP BY m3.global_message_id
     )
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
      echo "Deleted $RESULT messages (Total: $TOTAL_DELETED / $TOTAL_DUPES)"
    fi

    sleep 2
  fi
done
